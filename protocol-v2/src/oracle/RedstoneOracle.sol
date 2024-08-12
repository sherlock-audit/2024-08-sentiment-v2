// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// types
import { IOracle } from "../interfaces/IOracle.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { PrimaryProdDataServiceConsumerBase } from
    "@redstone-oracles-monorepo/packages/evm-connector/contracts/data-services/PrimaryProdDataServiceConsumerBase.sol";
// libraries
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

contract RedstoneCoreOracle is PrimaryProdDataServiceConsumerBase, IOracle {
    using Math for uint256;

    uint256 internal constant THREE_MINUTES = 60 * 3;

    // stale price threshold, prices older than this period are considered stale
    // the oracle can misreport stale prices for feeds with longer hearbeats
    uint256 public constant STALE_PRICE_THRESHOLD = 3600; // 1 hour

    address public immutable ASSET;
    uint256 public immutable ASSET_DECIMALS;

    bytes32 public immutable ETH_FEED_ID;
    bytes32 public immutable ASSET_FEED_ID;

    uint256 public ethUsdPrice;
    uint256 public assetUsdPrice;
    uint256 public priceTimestamp;

    // dataFeedIds[0] -> redstone feed id for ASSSET
    // dataFeedIds[0] -> redstone feed id for ETH
    bytes32[] internal dataFeedIds = new bytes32[](2);

    error RedstoneCoreOracle_StalePrice(address asset);

    constructor(address asset, bytes32 assetFeedId, bytes32 ethFeedId) {
        ASSET = asset;
        ASSET_DECIMALS = IERC20Metadata(asset).decimals();

        ASSET_FEED_ID = assetFeedId;
        ETH_FEED_ID = ethFeedId;

        dataFeedIds[0] = assetFeedId;
        dataFeedIds[1] = ethFeedId;
    }

    function updatePrice() external {
        // values[0] -> price of ASSET/USD
        // values[1] -> price of ETH/USD
        // values are scaled to 8 decimals
        uint256[] memory values = getOracleNumericValuesFromTxMsg(dataFeedIds);

        assetUsdPrice = values[0];
        ethUsdPrice = values[1];

        // RedstoneDefaultLibs.sol enforces that prices are not older than 3 mins. since it is not
        // possible to retrieve timestamps for individual prices being passed, we consider the worst
        // case and assume both prices are 3 mins old
        priceTimestamp = block.timestamp - THREE_MINUTES;
    }

    function getValueInEth(address, uint256 amt) external view returns (uint256) {
        if (priceTimestamp < block.timestamp - STALE_PRICE_THRESHOLD) revert RedstoneCoreOracle_StalePrice(ASSET);

        // scale amt to 18 decimals
        if (ASSET_DECIMALS <= 18) amt = amt * 10 ** (18 - ASSET_DECIMALS);
        else amt = amt / 10 ** (ASSET_DECIMALS - 18);

        // [ROUND] price is rounded down
        return amt.mulDiv(assetUsdPrice, ethUsdPrice);
    }
}
