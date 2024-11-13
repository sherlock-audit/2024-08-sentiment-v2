// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// types
import { IOracle } from "../interfaces/IOracle.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { PrimaryProdDataServiceConsumerBase } from
    "@redstone-oracles-monorepo/packages/evm-connector/contracts/data-services/PrimaryProdDataServiceConsumerBase.sol";
// libraries
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

contract RedstoneOracle is PrimaryProdDataServiceConsumerBase, IOracle {
    using Math for uint256;

    address internal constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 public constant STALE_PRICE_THRESHOLD = 3600; // 1 hour

    address public immutable ASSET;
    uint256 public immutable ASSET_DECIMALS;

    uint256 public immutable ETH_FEED_DECIMALS;
    uint256 public immutable ASSET_FEED_DECIMALS;

    bytes32 public immutable ETH_FEED_ID;
    bytes32 public immutable ASSET_FEED_ID;

    uint256 public ethUsdPrice;
    uint256 public assetUsdPrice;
    uint256 public priceTimestamp;

    // dataFeedIds[0] -> redstone feed id for ASSSET
    // dataFeedIds[0] -> redstone feed id for ETH
    bytes32[] internal dataFeedIds = new bytes32[](2);

    error RedstoneOracle_ZeroPrice(address asset);
    error RedstoneOracle_StalePrice(address asset);
    error RedstoneOracle_InvalidTimestamp(uint256 timestamp);

    constructor(
        address asset,
        bytes32 assetFeedId,
        bytes32 ethFeedId,
        uint256 assetFeedDecimals,
        uint256 ethFeedDecimals
    ) {
        ASSET = asset;
        ASSET_DECIMALS = IERC20Metadata(asset).decimals();

        ASSET_FEED_ID = assetFeedId;
        ETH_FEED_ID = ethFeedId;

        ASSET_FEED_DECIMALS = assetFeedDecimals;
        ETH_FEED_DECIMALS = ethFeedDecimals;

        dataFeedIds[0] = assetFeedId;
        dataFeedIds[1] = ethFeedId;
    }

    function updatePrice() external {
        // fetch ASSET/USD and ETH/USD price with package timestamp
        // values[0] -> ASSET/USD price with ASSET_FEED_DECIMALS decimals
        // values[1] -> ETH/USD price with ETH_FEED_DECIMALS decimals
        // timestamp -> data package timestamp in milliseconds
        (uint256[] memory values, uint256 timestamp) = getOracleNumericValuesAndTimestampFromTxMsg(dataFeedIds);

        // non-zero price checks
        if (values[0] == 0) revert RedstoneOracle_ZeroPrice(ASSET);
        if (values[1] == 0) revert RedstoneOracle_ZeroPrice(ETH);

        // scale ASSET/USD price to 18 decimals
        if (ASSET_FEED_DECIMALS <= 18) assetUsdPrice = values[0] * (10 ** (18 - ASSET_FEED_DECIMALS));
        else assetUsdPrice = values[0] / (10 ** (ASSET_FEED_DECIMALS - 18));

        // scale ETH/USD price to 18 decimals
        if (ETH_FEED_DECIMALS <= 18) ethUsdPrice = values[1] * (10 ** (18 - ETH_FEED_DECIMALS));
        else ethUsdPrice = values[1] / (10 ** (ETH_FEED_DECIMALS - 18));

        // update price timestamp with checks
        if (priceTimestamp > timestamp) revert RedstoneOracle_InvalidTimestamp(timestamp);
        priceTimestamp = timestamp;
    }

    function getValueInEth(address, uint256 amt) external view returns (uint256) {
        if (priceTimestamp < block.timestamp - STALE_PRICE_THRESHOLD) revert RedstoneOracle_StalePrice(ASSET);

        // scale amt to 18 decimals
        if (ASSET_DECIMALS <= 18) amt = amt * 10 ** (18 - ASSET_DECIMALS);
        else amt = amt / 10 ** (ASSET_DECIMALS - 18);

        // [ROUND] price is rounded down
        return amt.mulDiv(assetUsdPrice, ethUsdPrice);
    }
}
