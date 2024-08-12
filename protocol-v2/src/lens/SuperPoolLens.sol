// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                        SuperPoolLens
//////////////////////////////////////////////////////////////*/

// types
import { Pool } from "../Pool.sol";
import { RiskEngine } from "../RiskEngine.sol";
import { SuperPool } from "../SuperPool.sol";
import { IRateModel } from "../interfaces/IRateModel.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IOracle } from "src/interfaces/IOracle.sol";

// libraries
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title SuperPoolLens
/// @notice View-only utility contract to fetch SuperPool data
contract SuperPoolLens {
    using Math for uint256;

    /// @notice Address to the protocol's pool instance
    Pool public immutable POOL;

    /// @notice Address to the protocol's risk engine instance
    RiskEngine public immutable RISK_ENGINE;

    /// @param pool Address to the protocol's pool instance
    /// @param riskEngine Address to the protocol's risk engine instance
    constructor(address pool, address riskEngine) {
        POOL = Pool(pool);
        RISK_ENGINE = RiskEngine(riskEngine);
    }

    /// @title SuperPoolData
    /// @notice Comprehensive data container for SuperPool state including individual pool
    ///         deposits and aggregate data
    struct SuperPoolData {
        string name;
        address asset;
        uint256 idleAssets; // amount of assets that are yet to be deposited to underlying pools
        uint256 totalAssets;
        uint256 valueInEth;
        uint256 interestRate; // weighted yield rate from underlying pool deposits
        PoolDepositData[] deposits;
    }

    /// @notice Fetch current state for a given SuperPool
    /// @param _superPool Address of the super pool
    /// @return superPoolData Comprehensive current state data for the given super pool
    function getSuperPoolData(address _superPool) external view returns (SuperPoolData memory superPoolData) {
        SuperPool superPool = SuperPool(_superPool);
        uint256[] memory pools = superPool.pools(); // fetch underlying pools for given super pool

        // fetch data for each underlying pool
        uint256 poolsLength = pools.length;
        PoolDepositData[] memory deposits = new PoolDepositData[](poolsLength);
        for (uint256 i; i < poolsLength; ++i) {
            deposits[i] = getPoolDepositData(_superPool, pools[i]);
        }

        // aggregate data from underlying pools
        address asset = address(superPool.asset());
        uint256 totalAssets = superPool.totalAssets();
        return SuperPoolData({
            asset: asset,
            deposits: deposits,
            name: superPool.name(),
            totalAssets: totalAssets,
            valueInEth: _getValueInEth(asset, totalAssets),
            idleAssets: IERC20(asset).balanceOf(_superPool),
            interestRate: getSuperPoolInterestRate(_superPool)
        });
    }

    /// @title PoolDepositData
    /// @notice Generic data container for SuperPool deposits associated with a particular pool
    struct PoolDepositData {
        address asset;
        uint256 poolId;
        uint256 amount; // amount of assets deposited from the super pool into this pool
        uint256 valueInEth;
        uint256 interestRate;
    }

    /// @notice Fetch data for SuperPool deposits in a given pool
    /// @param superPool Address of the super pool
    /// @param poolId Id for the underlying pool
    /// @return poolDepositData Current data for deposits to `poolId` from the `superPool`
    function getPoolDepositData(
        address superPool,
        uint256 poolId
    ) public view returns (PoolDepositData memory poolDepositData) {
        address asset = POOL.getPoolAssetFor(poolId);
        uint256 amount = POOL.getAssetsOf(poolId, superPool);

        return PoolDepositData({
            asset: asset,
            amount: amount,
            poolId: poolId,
            valueInEth: _getValueInEth(asset, amount),
            interestRate: getPoolInterestRate(poolId)
        });
    }

    /// @title UserMultiDepositData
    /// @notice Container for a user's deposits across multiple super pools
    struct UserMultiDepositData {
        address owner;
        uint256 interestRate;
        uint256 totalValueInEth;
        UserDepositData[] deposits; // individual super pool deposit data for given user
    }

    /// @notice Fetch the current data for a given user's deposits across multiple super pools
    /// @param user Address of the user
    /// @param superPools List of SuperPool addresses to fetch data
    /// @return userMultiDepositData Current deposit data for `user` across each super pool
    function getUserMultiDepositData(
        address user,
        address[] calldata superPools
    ) public view returns (UserMultiDepositData memory userMultiDepositData) {
        UserDepositData[] memory deposits = new UserDepositData[](superPools.length);

        uint256 totalValueInEth;
        uint256 weightedDeposit;

        uint256 superPoolsLength = superPools.length;
        for (uint256 i; i < superPoolsLength; ++i) {
            deposits[i] = getUserDepositData(user, superPools[i]);

            totalValueInEth += deposits[i].valueInEth;

            // [ROUND] deposit weights are rounded up, in favor of the user
            weightedDeposit += (deposits[i].valueInEth).mulDiv(deposits[i].interestRate, 1e18, Math.Rounding.Up);
        }

        // [ROUND] interestRate is rounded up, in favor of the user
        uint256 interestRate =
            (totalValueInEth != 0) ? weightedDeposit.mulDiv(1e18, totalValueInEth, Math.Rounding.Up) : 0;

        return UserMultiDepositData({
            owner: user,
            deposits: deposits,
            totalValueInEth: totalValueInEth,
            interestRate: interestRate
        });
    }

    /// @title UserDepositData
    /// @notice Container for a user's deposit in a single SuperPool
    struct UserDepositData {
        address owner;
        address asset;
        address superPool;
        uint256 amount;
        uint256 valueInEth;
        uint256 interestRate;
    }

    /// @notice Fetch a particular user's deposit data for a given super pool
    /// @param user Address of the user
    /// @param _superPool Address of the superPool
    /// @return userDepositData Current user deposit data for the given super pool
    function getUserDepositData(
        address user,
        address _superPool
    ) public view returns (UserDepositData memory userDepositData) {
        SuperPool superPool = SuperPool(_superPool);
        address asset = address(superPool.asset());
        uint256 amount = superPool.previewRedeem(superPool.balanceOf(user));

        return UserDepositData({
            owner: user,
            asset: asset,
            amount: amount,
            superPool: _superPool,
            valueInEth: _getValueInEth(asset, amount),
            interestRate: getSuperPoolInterestRate(_superPool)
        });
    }

    /// @notice Fetch current borrow interest rate for a given pool
    /// @param poolId Id of the underlying pool
    /// @return interestRate current interest rate for the given pool
    function getPoolInterestRate(uint256 poolId) public view returns (uint256 interestRate) {
        IRateModel irm = IRateModel(POOL.getRateModelFor(poolId));
        return irm.getInterestRate(POOL.getTotalBorrows(poolId), POOL.getTotalAssets(poolId));
    }

    /// @notice Fetch the weighted interest yield for a given super pool
    /// @param _superPool Address of the super pool
    /// @return interestRate current weighted interest yield for the given super pool
    function getSuperPoolInterestRate(address _superPool) public view returns (uint256 interestRate) {
        SuperPool superPool = SuperPool(_superPool);
        uint256 totalAssets = superPool.totalAssets();

        if (totalAssets == 0) return 0;

        uint256 weightedAssets;
        uint256[] memory pools = superPool.pools();
        uint256 poolsLength = pools.length;
        for (uint256 i; i < poolsLength; ++i) {
            uint256 assets = POOL.getAssetsOf(pools[i], _superPool);
            weightedAssets += assets * getPoolInterestRate(pools[i]);
        }

        return weightedAssets / totalAssets;
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
