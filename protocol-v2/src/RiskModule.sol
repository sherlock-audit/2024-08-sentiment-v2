// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                            RiskModule
//////////////////////////////////////////////////////////////*/

// types
import { Pool } from "./Pool.sol";
import { Position } from "./Position.sol";
import { AssetData, DebtData } from "./PositionManager.sol";
import { Registry } from "./Registry.sol";
import { RiskEngine } from "./RiskEngine.sol";
import { IOracle } from "./interfaces/IOracle.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// libraries
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title RiskModule
contract RiskModule {
    using Math for uint256;

    /// @notice Sentiment Registry Pool registry key hash
    /// @dev keccak(SENTIMENT_POOL_KEY)
    bytes32 public constant SENTIMENT_POOL_KEY = 0x1a99cbf6006db18a0e08427ff11db78f3ea1054bc5b9d48122aae8d206c09728;
    /// @notice Sentiment Risk Engine registry key hash
    /// @dev keccak(SENTIMENT_RISK_ENGINE_KEY)
    bytes32 public constant SENTIMENT_RISK_ENGINE_KEY =
        0x5b6696788621a5d6b5e3b02a69896b9dd824ebf1631584f038a393c29b6d7555;

    /// @notice The discount on assets when liquidating, out of 1e18
    uint256 public immutable LIQUIDATION_DISCOUNT;
    /// @notice The updateable registry as a part of the 2step initialization process
    Registry public immutable REGISTRY;
    /// @notice Sentiment Singleton Pool
    Pool public pool;
    /// @notice Sentiment Risk Engine
    RiskEngine public riskEngine;

    /// @notice Value of assets seized by the liquidator exceeds liquidation discount
    error RiskModule_SeizedTooMuch(uint256 seizedValue, uint256 maxSeizedValue);
    /// @notice Position contains an asset that is not supported by a pool that it borrows from
    error RiskModule_UnsupportedAsset(address position, uint256 poolId, address asset);
    /// @notice Minimum assets required in a position with non-zero debt cannot be zero
    error RiskModule_ZeroMinReqAssets();
    /// @notice Cannot liquidate healthy positions
    error RiskModule_LiquidateHealthyPosition(address position);
    /// @notice Position does not have any bad debt
    error RiskModule_NoBadDebt(address position);

    /// @notice Constructor for Risk Module, which should be registered with the RiskEngine
    /// @param registry_ The address of the registry contract
    /// @param liquidationDiscount_ The discount on assets when liquidating, out of 1e18
    constructor(address registry_, uint256 liquidationDiscount_) {
        REGISTRY = Registry(registry_);
        LIQUIDATION_DISCOUNT = liquidationDiscount_;
    }

    /// @notice Updates the pool and risk engine from the registry
    function updateFromRegistry() external {
        pool = Pool(REGISTRY.addressFor(SENTIMENT_POOL_KEY));
        riskEngine = RiskEngine(REGISTRY.addressFor(SENTIMENT_RISK_ENGINE_KEY));
    }

    /// @notice Evaluates whether a given position is healthy based on the debt and asset values
    function isPositionHealthy(address position) public view returns (bool) {
        // a position can have four states:
        // 1. (zero debt, zero assets) -> healthy
        // 2. (zero debt, non-zero assets) -> healthy
        // 3. (non-zero debt, zero assets) -> unhealthy
        // 4. (non-zero assets, non-zero debt) -> determined by weighted ltv

        (uint256 totalDebtValue, uint256[] memory debtPools, uint256[] memory debtValueForPool) =
            _getPositionDebtData(position);
        if (totalDebtValue == 0) return true; // (zero debt, zero assets) AND (zero debt, non-zero assets)

        (uint256 totalAssetValue, address[] memory positionAssets, uint256[] memory positionAssetWeight) =
            _getPositionAssetData(position);
        if (totalAssetValue == 0) return false; // (non-zero debt, zero assets)

        uint256 minReqAssetValue =
            _getMinReqAssetValue(debtPools, debtValueForPool, positionAssets, positionAssetWeight, position);
        return totalAssetValue >= minReqAssetValue; // (non-zero debt, non-zero assets)
    }

    /// @notice Fetch risk-associated data for a given position
    /// @param position The address of the position to get the risk data for
    /// @return totalAssetValue The total asset value of the position
    /// @return totalDebtValue The total debt value of the position
    /// @return minReqAssetValue The minimum required asset value for the position to be healthy
    function getRiskData(address position) external view returns (uint256, uint256, uint256) {
        (uint256 totalAssetValue, address[] memory positionAssets, uint256[] memory positionAssetWeight) =
            _getPositionAssetData(position);

        (uint256 totalDebtValue, uint256[] memory debtPools, uint256[] memory debtValueForPool) =
            _getPositionDebtData(position);

        if (totalAssetValue == 0 || totalDebtValue == 0) return (totalAssetValue, totalDebtValue, 0);

        uint256 minReqAssetValue =
            _getMinReqAssetValue(debtPools, debtValueForPool, positionAssets, positionAssetWeight, position);

        return (totalAssetValue, totalDebtValue, minReqAssetValue);
    }

    /// @notice Used to validate liquidator data and value of assets seized
    /// @param position Position being liquidated
    /// @param debtData The debt data for the position
    /// @param assetData The asset data for the position
    function validateLiquidation(
        address position,
        DebtData[] calldata debtData,
        AssetData[] calldata assetData
    ) external view {
        // position must breach risk thresholds before liquidation
        if (isPositionHealthy(position)) revert RiskModule_LiquidateHealthyPosition(position);

        _validateSeizedAssetValue(position, debtData, assetData, LIQUIDATION_DISCOUNT);
    }

    /// @notice Verify if a given position has bad debt
    function validateBadDebt(address position) external view {
        uint256 totalDebtValue = getTotalDebtValue(position);
        uint256 totalAssetValue = getTotalAssetValue(position);
        if (totalAssetValue > totalDebtValue) revert RiskModule_NoBadDebt(position);
    }

    function _validateSeizedAssetValue(
        address position,
        DebtData[] calldata debtData,
        AssetData[] calldata assetData,
        uint256 discount
    ) internal view {
        // compute value of debt repaid by the liquidator
        uint256 debtRepaidValue;
        uint256 debtLength = debtData.length;
        for (uint256 i; i < debtLength; ++i) {
            uint256 poolId = debtData[i].poolId;
            uint256 amt = debtData[i].amt;
            if (amt == type(uint256).max) amt = pool.getBorrowsOf(poolId, position);
            address poolAsset = pool.getPoolAssetFor(poolId);
            IOracle oracle = IOracle(riskEngine.getOracleFor(poolAsset));
            debtRepaidValue += oracle.getValueInEth(poolAsset, amt);
        }

        // compute value of assets seized by the liquidator
        uint256 assetSeizedValue;
        uint256 assetDataLength = assetData.length;
        for (uint256 i; i < assetDataLength; ++i) {
            IOracle oracle = IOracle(riskEngine.getOracleFor(assetData[i].asset));
            assetSeizedValue += oracle.getValueInEth(assetData[i].asset, assetData[i].amt);
        }

        // max asset value that can be seized by the liquidator
        uint256 maxSeizedAssetValue = debtRepaidValue.mulDiv(1e18, (1e18 - discount));
        if (assetSeizedValue > maxSeizedAssetValue) {
            revert RiskModule_SeizedTooMuch(assetSeizedValue, maxSeizedAssetValue);
        }
    }

    /// @notice Gets the ETH debt value a given position owes to a particular pool
    function getDebtValueForPool(address position, uint256 poolId) public view returns (uint256) {
        address asset = pool.getPoolAssetFor(poolId);
        IOracle oracle = IOracle(riskEngine.getOracleFor(asset));
        return oracle.getValueInEth(asset, pool.getBorrowsOf(poolId, position));
    }

    /// @notice Gets the total debt owed by a position in ETH
    function getTotalDebtValue(address position) public view returns (uint256) {
        uint256[] memory debtPools = Position(payable(position)).getDebtPools();

        uint256 totalDebtValue;
        uint256 debtPoolsLength = debtPools.length;
        for (uint256 i; i < debtPoolsLength; ++i) {
            totalDebtValue += getDebtValueForPool(position, debtPools[i]);
        }

        return totalDebtValue;
    }

    /// @notice Gets the ETH value for a particular asset in a given position
    function getAssetValue(address position, address asset) public view returns (uint256) {
        IOracle oracle = IOracle(riskEngine.getOracleFor(asset));
        uint256 amt = IERC20(asset).balanceOf(position);
        return oracle.getValueInEth(asset, amt);
    }

    /// @notice Gets the total ETH value of assets in a position
    function getTotalAssetValue(address position) public view returns (uint256) {
        address[] memory positionAssets = Position(payable(position)).getPositionAssets();

        uint256 totalAssetValue;
        uint256 positionAssetsLength = positionAssets.length;
        for (uint256 i; i < positionAssetsLength; ++i) {
            totalAssetValue += getAssetValue(position, positionAssets[i]);
        }

        return totalAssetValue;
    }

    function _getPositionDebtData(address position)
        internal
        view
        returns (uint256, uint256[] memory, uint256[] memory)
    {
        uint256 totalDebtValue;
        uint256[] memory debtPools = Position(payable(position)).getDebtPools();
        uint256[] memory debtValueForPool = new uint256[](debtPools.length);

        uint256 debtPoolsLength = debtPools.length;
        for (uint256 i; i < debtPoolsLength; ++i) {
            uint256 debt = getDebtValueForPool(position, debtPools[i]);
            debtValueForPool[i] = debt;
            totalDebtValue += debt;
        }

        return (totalDebtValue, debtPools, debtValueForPool);
    }

    function _getPositionAssetData(address position)
        internal
        view
        returns (uint256, address[] memory, uint256[] memory)
    {
        uint256 totalAssetValue;

        address[] memory positionAssets = Position(payable(position)).getPositionAssets();
        uint256 positionAssetsLength = positionAssets.length;
        uint256[] memory positionAssetData = new uint256[](positionAssetsLength);

        for (uint256 i; i < positionAssetsLength; ++i) {
            uint256 assets = getAssetValue(position, positionAssets[i]);
            // positionAssetData[i] stores value of positionAssets[i] in eth
            positionAssetData[i] = assets;
            totalAssetValue += assets;
        }

        if (totalAssetValue == 0) return (0, positionAssets, positionAssetData);

        for (uint256 i; i < positionAssetsLength; ++i) {
            // positionAssetData[i] stores weight of positionAsset[i]
            // wt of positionAsset[i] = (value of positionAsset[i]) / (total position assets value)
            positionAssetData[i] = positionAssetData[i].mulDiv(1e18, totalAssetValue);
        }

        return (totalAssetValue, positionAssets, positionAssetData);
    }

    function _getMinReqAssetValue(
        uint256[] memory debtPools,
        uint256[] memory debtValuleForPool,
        address[] memory positionAssets,
        uint256[] memory wt,
        address position
    ) internal view returns (uint256) {
        uint256 minReqAssetValue;

        // O(pools.len * positionAssets.len)
        uint256 debtPoolsLength = debtPools.length;
        uint256 positionAssetsLength = positionAssets.length;
        for (uint256 i; i < debtPoolsLength; ++i) {
            for (uint256 j; j < positionAssetsLength; ++j) {
                uint256 ltv = riskEngine.ltvFor(debtPools[i], positionAssets[j]);

                // revert with pool id and the asset that is not supported by the pool
                if (ltv == 0) revert RiskModule_UnsupportedAsset(position, debtPools[i], positionAssets[j]);

                // debt is weighted in proportion to value of position assets. if your position
                // consists of 60% A and 40% B, then 60% of the debt is assigned to be backed by A
                // and 40% by B. this is iteratively computed for each pool the position borrows from
                minReqAssetValue += debtValuleForPool[i].mulDiv(wt[j], ltv, Math.Rounding.Up);
            }
        }

        if (minReqAssetValue == 0) revert RiskModule_ZeroMinReqAssets();
        return minReqAssetValue;
    }
}
