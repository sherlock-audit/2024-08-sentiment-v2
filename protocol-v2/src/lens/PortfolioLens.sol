// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                        PortfolioLens
//////////////////////////////////////////////////////////////*/

// types
import { Pool } from "../Pool.sol";
import { Position } from "../Position.sol";
import { PositionManager } from "../PositionManager.sol";
import { RiskEngine } from "../RiskEngine.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IOracle } from "src/interfaces/IOracle.sol";
import { IRateModel } from "src/interfaces/IRateModel.sol";

// contracts
import { BeaconProxy } from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

/// @title PortfolioLens
/// @notice View-only utility contract to fetch position state
contract PortfolioLens {
    /// @notice Address to the protocol's pool instance
    Pool public immutable POOL;

    /// @notice Address to the protocol's risk engine instance
    RiskEngine public immutable RISK_ENGINE;

    /// @notice Address to the protocol's position manager instance
    PositionManager public immutable POSITION_MANAGER;

    /// @param pool Address to the protocol's pool instance
    /// @param riskEngine Address to the protocol's risk engine instance
    /// @param positionManager Address to the protocol's position manager instance
    constructor(address pool, address riskEngine, address positionManager) {
        POOL = Pool(pool);
        RISK_ENGINE = RiskEngine(riskEngine);
        POSITION_MANAGER = PositionManager(positionManager);
    }

    /// @title PortfolioData
    /// @notice Container for data associated with multiple positions
    struct PortfolioData {
        PositionData[] positions;
    }

    /// @notice Fetch current state for multiple positions at once
    /// @param positions Array of position addresses
    /// @return portfolioData Array of current position data for each given position
    function getPortfolioData(address[] calldata positions) public view returns (PortfolioData memory portfolioData) {
        PositionData[] memory positionData = new PositionData[](positions.length);

        // fetch data for each position
        uint256 positionsLength = positions.length;
        for (uint256 i; i < positionsLength; ++i) {
            positionData[i] = getPositionData(positions[i]);
        }

        return PortfolioData({ positions: positionData });
    }

    /// @title PositionData
    /// @notice Container for data associated with a single position
    struct PositionData {
        address position;
        address owner;
        AssetData[] assets; // data for each asset held by the position
        DebtData[] debts; // data for each pool the position is actively borrowing from
    }

    /// @notice Fetch current state for a given position
    /// @param position Address of the position
    /// @return positionData Current position data for the given position
    function getPositionData(address position) public view returns (PositionData memory positionData) {
        return PositionData({
            position: position,
            owner: POSITION_MANAGER.ownerOf(position),
            assets: getAssetData(position),
            debts: getDebtData(position)
        });
    }

    /// @title AssetData
    /// @notice Generic container for position asset data
    struct AssetData {
        address asset;
        uint256 amount; // amount of asset currently in the position
        uint256 valueInEth;
    }

    /// @notice Fetch data for all assets currently held by a position
    /// @param position Address of the position
    /// @return assetData List of data for assets currently held by the given position
    /// @dev Could return values with zero amount if AddToken / RemoveToken has not been called
    function getAssetData(address position) public view returns (AssetData[] memory assetData) {
        address[] memory positionAssets = Position(payable(position)).getPositionAssets();

        // fetch data for each position asset
        uint256 positionAssetsLength = positionAssets.length;
        assetData = new AssetData[](positionAssetsLength);
        for (uint256 i; i < positionAssetsLength; ++i) {
            address asset = positionAssets[i];
            uint256 amount = IERC20(positionAssets[i]).balanceOf(position);
            assetData[i] = AssetData({ asset: asset, amount: amount, valueInEth: _getValueInEth(asset, amount) });
        }

        return assetData;
    }

    /// @title DebtData
    /// @notice Generic container for position debt data
    struct DebtData {
        uint256 poolId;
        address asset;
        uint256 amount;
        uint256 valueInEth;
        uint256 interestRate;
    }

    /// @notice Fetch data for all active debt associated a given position
    /// @param position Address of the position
    /// @return debtData List of pool-wise debt data currently owed by the given position
    function getDebtData(address position) public view returns (DebtData[] memory debtData) {
        uint256[] memory debtPools = Position(payable(position)).getDebtPools();

        // fetch debt data for each pool
        uint256 debtPoolsLength = debtPools.length;
        debtData = new DebtData[](debtPoolsLength);
        for (uint256 i; i < debtPoolsLength; ++i) {
            uint256 poolId = debtPools[i];
            address poolAsset = POOL.getPoolAssetFor(poolId);
            uint256 totalAssets = POOL.getTotalAssets(poolId);
            uint256 totalBorrows = POOL.getTotalBorrows(poolId);
            uint256 borrowAmt = POOL.getBorrowsOf(poolId, position);

            debtData[i] = DebtData({
                poolId: poolId,
                asset: poolAsset,
                amount: borrowAmt,
                valueInEth: _getValueInEth(poolAsset, borrowAmt),
                interestRate: IRateModel(POOL.getRateModelFor(poolId)).getInterestRate(totalBorrows, totalAssets)
            });
        }

        return debtData;
    }

    /// @notice Utility function to predict the CREATE2 address for a new position
    /// @param owner Address of the new position owner
    /// @param salt CREATE2 salt for the new position
    /// @return newPosition Predicted address for the new position
    /// @return available Boolean which is false if the predicted position address already has code deployed to it
    function predictAddress(address owner, bytes32 salt) external view returns (address newPosition, bool available) {
        // hash salt with owner to mitigate frontrun attacks
        salt = keccak256(abi.encodePacked(owner, salt));

        bytes memory creationCode =
            abi.encodePacked(type(BeaconProxy).creationCode, abi.encode(address(POSITION_MANAGER.positionBeacon()), ""));

        newPosition = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), POSITION_MANAGER, salt, keccak256(creationCode)))))
        );

        return (newPosition, newPosition.code.length == 0);
    }

    /// @dev Compute the ETH value scaled to 18 decimals for a given amount of an asset
    function _getValueInEth(address asset, uint256 amt) internal view returns (uint256) {
        IOracle oracle = IOracle(RISK_ENGINE.getOracleFor(asset));

        // oracles could revert, but lens calls must not
        try oracle.getValueInEth(asset, amt) returns (uint256 valueInEth) {
            return valueInEth;
        } catch {
            return 0;
        }
    }
}
