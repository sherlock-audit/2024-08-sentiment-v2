// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

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

    uint256 internal constant WAD = 1e18;
    /// @notice Sentiment Registry Pool registry key hash
    /// @dev keccak(SENTIMENT_POOL_KEY)
    bytes32 public constant SENTIMENT_POOL_KEY = 0x1a99cbf6006db18a0e08427ff11db78f3ea1054bc5b9d48122aae8d206c09728;
    /// @notice Sentiment Risk Engine registry key hash
    /// @dev keccak(SENTIMENT_RISK_ENGINE_KEY)
    bytes32 public constant SENTIMENT_RISK_ENGINE_KEY =
        0x5b6696788621a5d6b5e3b02a69896b9dd824ebf1631584f038a393c29b6d7555;

    /// @notice Protocol liquidation fee, out of 1e18
    uint256 public immutable LIQUIDATION_FEE;
    /// @notice The discount on assets when liquidating, out of 1e18
    uint256 public immutable LIQUIDATION_DISCOUNT;
    /// @notice The updateable registry as a part of the 2step initialization process
    Registry public immutable REGISTRY;
    /// @notice Sentiment Singleton Pool
    Pool public pool;
    /// @notice Sentiment Risk Engine
    RiskEngine public riskEngine;

    /// @notice Pool address was updated
    event PoolSet(address pool);
    /// @notice Risk Engine address was updated
    event RiskEngineSet(address riskEngine);

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
    /// @notice Seized asset does not belong to to the position's asset list
    error RiskModule_SeizeInvalidAsset(address position, address asset);
    /// @notice Liquidation DebtData is invalid
    error RiskModule_InvalidDebtData(uint256 poolId);
    /// @notice Liquidation AssetData is invalid
    error RiskModule_InvalidAssetData(address asset);

    /// @notice Constructor for Risk Module, which should be registered with the RiskEngine
    /// @param registry_ The address of the registry contract
    /// @param liquidationDiscount_ The discount on assets when liquidating, out of 1e18
    constructor(address registry_, uint256 liquidationDiscount_, uint256 liquidationFee_) {
        REGISTRY = Registry(registry_);
        LIQUIDATION_DISCOUNT = liquidationDiscount_;
        LIQUIDATION_FEE = liquidationFee_;
    }

    /// @notice Updates the pool and risk engine from the registry
    function updateFromRegistry() external {
        pool = Pool(REGISTRY.addressFor(SENTIMENT_POOL_KEY));
        riskEngine = RiskEngine(REGISTRY.addressFor(SENTIMENT_RISK_ENGINE_KEY));
        emit PoolSet(address(pool));
        emit RiskEngineSet(address(riskEngine));
    }

    /// @notice Fetch position health factor
    function getPositionHealthFactor(address position) public view returns (uint256) {
        // a position can have multiple states:
        // 1. (zero debt, zero assets) -> max health
        // 2. (zero debt, non-zero assets) -> max health
        // 3. (non-zero debt, zero assets) -> invalid state, zero health
        // 4. (non-zero debt, non-zero assets) AND (debt > assets) -> bad debt, zero health
        // 5. (non-zero debt, non-zero assets) AND (assets >= debt) -> determined by weighted ltv

        (uint256 totalAssets, uint256 totalDebt, uint256 weightedLtv) = getRiskData(position);
        if (totalDebt == 0) return type(uint256).max; // (zero debt, zero assets) AND (zero debt, non-zero assets)
        if (totalDebt > totalAssets) return 0; // (non-zero debt, zero assets) AND bad debt
        return weightedLtv.mulDiv(totalAssets, totalDebt); // (non-zero debt, non-zero assets) AND no bad debt
    }

    /// @notice Fetch risk data for a position - total assets and debt in ETH, and its weighted LTV
    /// @dev weightedLtv is zero if either total assets or total debt is zero
    function getRiskData(address position) public view returns (uint256, uint256, uint256) {
        (uint256 totalDebt, uint256[] memory debtPools, uint256[] memory debtValue) = getDebtData(position);
        (uint256 totalAssets, address[] memory positionAssets, uint256[] memory assetValue) = getAssetData(position);
        uint256 weightedLtv =
            _getWeightedLtv(position, totalDebt, debtPools, debtValue, totalAssets, positionAssets, assetValue);
        return (totalAssets, totalDebt, weightedLtv);
    }

    /// @notice Fetch debt data for position - total debt in ETH, active debt pools, and debt for each pool in ETH
    function getDebtData(address position) public view returns (uint256, uint256[] memory, uint256[] memory) {
        uint256 totalDebt;
        uint256[] memory debtPools = Position(payable(position)).getDebtPools();
        uint256[] memory debtValue = new uint256[](debtPools.length);

        uint256 debtPoolsLength = debtPools.length;
        for (uint256 i; i < debtPoolsLength; ++i) {
            address poolAsset = pool.getPoolAssetFor(debtPools[i]);
            uint256 borrowAmt = pool.getBorrowsOf(debtPools[i], position);
            uint256 debtInEth = riskEngine.getValueInEth(poolAsset, borrowAmt);
            debtValue[i] = debtInEth;
            totalDebt += debtInEth;
        }
        return (totalDebt, debtPools, debtValue);
    }

    /// @notice Fetch asset data for a position - total assets in ETH, position assets, and value of each asset in ETH
    function getAssetData(address position) public view returns (uint256, address[] memory, uint256[] memory) {
        uint256 totalAssets;
        address[] memory positionAssets = Position(payable(position)).getPositionAssets();
        uint256 positionAssetsLength = positionAssets.length;
        uint256[] memory assetValue = new uint256[](positionAssetsLength);

        for (uint256 i; i < positionAssetsLength; ++i) {
            uint256 amt = IERC20(positionAssets[i]).balanceOf(position);
            uint256 assetsInEth = riskEngine.getValueInEth(positionAssets[i], amt);
            assetValue[i] = assetsInEth;
            totalAssets += assetsInEth;
        }
        return (totalAssets, positionAssets, assetValue);
    }

    /// @notice Fetch weighted Ltv for a position
    function getWeightedLtv(address position) public view returns (uint256) {
        (uint256 totalDebt, uint256[] memory debtPools, uint256[] memory debtValue) = getDebtData(position);
        (uint256 totalAssets, address[] memory positionAssets, uint256[] memory assetValue) = getAssetData(position);
        return _getWeightedLtv(position, totalDebt, debtPools, debtValue, totalAssets, positionAssets, assetValue);
    }

    function _getWeightedLtv(
        address position,
        uint256 totalDebt,
        uint256[] memory debtPools,
        uint256[] memory debtValue,
        uint256 totalAssets,
        address[] memory positionAssets,
        uint256[] memory assetValue
    )
        internal
        view
        returns (uint256 weightedLtv)
    {
        // handle empty, zero-debt, bad debt, and invalid position states
        if (totalDebt == 0 || totalAssets == 0 || totalDebt > totalAssets) return 0;

        uint256 debtPoolsLen = debtPools.length;
        uint256 positionAssetsLen = positionAssets.length;
        // O(debtPools.length * positionAssets.length)
        for (uint256 i; i < debtPoolsLen; ++i) {
            for (uint256 j; j < positionAssetsLen; ++j) {
                uint256 ltv = riskEngine.ltvFor(debtPools[i], positionAssets[j]);
                // every position asset must have a non-zero ltv in every debt pool
                if (ltv == 0) revert RiskModule_UnsupportedAsset(position, debtPools[i], positionAssets[j]);
                // ltv is weighted over two dimensions - proportion of debt value owed to a pool as a share of the
                // total position debt and proportion of position asset value as a share of total position value
                weightedLtv += debtValue[i].mulDiv(assetValue[j], WAD).mulDiv(ltv, WAD);
            }
        }
        weightedLtv = weightedLtv.mulDiv(WAD, totalAssets).mulDiv(WAD, totalDebt);
    }

    /// @notice Used to validate liquidator data and value of assets seized
    /// @param position Position being liquidated
    /// @param debtData The debt data for the position
    /// @param assetData The asset data for the position
    function validateLiquidation(
        address position,
        DebtData[] calldata debtData,
        AssetData[] calldata assetData
    )
        external
        view
        returns (uint256, uint256, DebtData[] memory, AssetData[] memory)
    {
        // ensure position is unhealthy
        uint256 healthFactor = getPositionHealthFactor(position);
        if (healthFactor >= WAD) revert RiskModule_LiquidateHealthyPosition(position);

        // parse data for repayment and seizure
        (uint256 totalRepayValue, DebtData[] memory repayData) = _getRepayData(position, debtData);
        (uint256 totalSeizeValue, AssetData[] memory seizeData) = _getSeizeData(position, assetData);

        // verify liquidator does not seize too much
        uint256 maxSeizeValue = totalRepayValue.mulDiv(1e18, (1e18 - LIQUIDATION_DISCOUNT));
        if (totalSeizeValue > maxSeizeValue) revert RiskModule_SeizedTooMuch(totalSeizeValue, maxSeizeValue);

        // compute protocol liquidation fee as a portion of liquidator profit, if any
        uint256 liqFee;
        if (totalSeizeValue > totalRepayValue) {
            liqFee = (totalSeizeValue - totalRepayValue).mulDiv(LIQUIDATION_FEE, totalSeizeValue);
        }

        return (healthFactor, liqFee, repayData, seizeData);
    }

    /// @notice validate bad debt liquidation call
    /// @dev Positions with bad debt cannot be partially liquidated
    function validateBadDebtLiquidation(
        address position,
        DebtData[] calldata debtData
    )
        external
        view
        returns (DebtData[] memory, AssetData[] memory)
    {
        // verify position has bad debt
        (uint256 totalAssetValue, uint256 totalDebtValue,) = getRiskData(position);
        if (totalAssetValue >= totalDebtValue) revert RiskModule_NoBadDebt(position);

        // parse repayment data
        (uint256 totalRepayValue, DebtData[] memory repayData) = _getRepayData(position, debtData);

        // verify that liquidator repays enough to seize all position assets
        uint256 maxSeizeValue = totalRepayValue.mulDiv(1e18, (1e18 - LIQUIDATION_DISCOUNT));
        if (totalAssetValue > maxSeizeValue) revert RiskModule_SeizedTooMuch(totalAssetValue, maxSeizeValue);

        // generate asset seizure data - since bad debt liquidations are not partial, all assets are seized
        AssetData[] memory seizeData = _getBadDebtSeizeData(position);

        return (repayData, seizeData);
    }

    function _getRepayData(
        address position,
        DebtData[] calldata debtData
    )
        internal
        view
        returns (uint256 totalRepayValue, DebtData[] memory repayData)
    {
        _validateDebtData(position, debtData);
        uint256 debtDataLen = debtData.length;
        repayData = debtData; // copy debtData and replace all type(uint).max with repay amounts
        for (uint256 i; i < debtDataLen; ++i) {
            uint256 poolId = repayData[i].poolId;
            uint256 repayAmt = repayData[i].amt;
            if (repayAmt == type(uint256).max) {
                repayAmt = pool.getBorrowsOf(poolId, position);
                repayData[i].amt = repayAmt;
            }
            totalRepayValue += riskEngine.getValueInEth(pool.getPoolAssetFor(poolId), repayAmt);
        }
    }

    function _getSeizeData(
        address position,
        AssetData[] calldata assetData
    )
        internal
        view
        returns (uint256 totalSeizeValue, AssetData[] memory seizeData)
    {
        _validateAssetData(position, assetData);
        uint256 assetDataLen = assetData.length;
        seizeData = assetData; // copy assetData and replace all type(uint).max with position asset balances
        for (uint256 i; i < assetDataLen; ++i) {
            address asset = seizeData[i].asset;
            // ensure assetData[i] is in the position asset list
            if (Position(payable(position)).hasAsset(asset) == false) {
                revert RiskModule_SeizeInvalidAsset(position, asset);
            }
            uint256 seizeAmt = seizeData[i].amt;
            if (seizeAmt == type(uint256).max) {
                seizeAmt = IERC20(asset).balanceOf(position);
                seizeData[i].amt = seizeAmt;
            }
            totalSeizeValue += riskEngine.getValueInEth(asset, seizeAmt);
        }
    }

    // since bad debt liquidations cannot be partial, all position assets are seized
    function _getBadDebtSeizeData(address position) internal view returns (AssetData[] memory) {
        address[] memory positionAssets = Position(payable(position)).getPositionAssets();
        uint256 positionAssetsLength = positionAssets.length;
        AssetData[] memory seizeData = new AssetData[](positionAssets.length);

        for (uint256 i; i < positionAssetsLength; ++i) {
            address asset = positionAssets[i];
            uint256 amt = IERC20(positionAssets[i]).balanceOf(position);
            seizeData[i] = AssetData({ asset: asset, amt: amt });
        }
        return seizeData;
    }

    // ensure DebtData has no duplicates by enforcing an ascending order of poolIds
    // ensure repaid pools are in the debt array for the position
    function _validateDebtData(address position, DebtData[] memory debtData) internal view {
        uint256 debtDataLen = debtData.length;
        if (debtDataLen == 0) return;

        uint256 lastPoolId = debtData[0].poolId;
        if (Position(payable(position)).hasDebt(lastPoolId) == false) revert RiskModule_InvalidDebtData(lastPoolId);

        for (uint256 i = 1; i < debtDataLen; ++i) {
            uint256 poolId = debtData[i].poolId;
            if (poolId <= lastPoolId) revert RiskModule_InvalidDebtData(poolId);
            if (Position(payable(position)).hasDebt(poolId) == false) revert RiskModule_InvalidDebtData(poolId);
            lastPoolId = poolId;
        }
    }

    // ensure assetData has no duplicates by enforcing an ascending order of assets
    // ensure seized assets are in the assets array for the position
    function _validateAssetData(address position, AssetData[] memory assetData) internal view {
        uint256 assetDataLen = assetData.length;
        if (assetDataLen == 0) return;

        address lastAsset = assetData[0].asset;
        if (Position(payable(position)).hasAsset(lastAsset) == false) revert RiskModule_InvalidAssetData(lastAsset);

        for (uint256 i = 1; i < assetDataLen; ++i) {
            address asset = assetData[i].asset;
            if (asset <= lastAsset) revert RiskModule_InvalidAssetData(asset);
            if (Position(payable(position)).hasAsset(asset) == false) revert RiskModule_InvalidAssetData(asset);
            lastAsset = asset;
        }
    }
}
