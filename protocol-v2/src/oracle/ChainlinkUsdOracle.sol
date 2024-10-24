// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IOracle } from "../interfaces/IOracle.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title IAggregatorV3
/// @notice Chainlink Aggregator v3 interface
interface IAggregatorV3 {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    function decimals() external view returns (uint8);
}

/// @title ChainlinkUsdOracle
/// @notice Oracle implementation to price assets using USD-denominated chainlink feeds
contract ChainlinkUsdOracle is Ownable, IOracle {
    using Math for uint256;

    /// @dev internal alias for native ETH
    address private constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    /// @notice L2 sequencer uptime grace period during which prices are treated as stale
    uint256 public constant SEQ_GRACE_PERIOD = 3600; // 1 hour

    /// @notice Chainlink arbitrum sequencer uptime feed
    IAggregatorV3 public immutable ARB_SEQ_FEED;

    struct PriceFeed {
        address feed;
        uint256 feedDecimals;
        uint256 assetDecimals;
        uint256 stalePriceThreshold;
    }

    /// @notice Fetch the ETH-denominated price feed associated with a given asset
    /// @dev returns address(0) if there is no associated feed
    mapping(address asset => PriceFeed feed) public priceFeedFor;

    /// @notice New Usd-denomiated chainlink feed has been associated with an asset
    event FeedSet(address indexed asset, PriceFeed feedData);

    /// @notice L2 sequencer is experiencing downtime
    error ChainlinkUsdOracle_SequencerDown();
    /// @notice L2 Sequencer has recently recovered from downtime and is in its grace period
    error ChainlinkUsdOracle_GracePeriodNotOver();
    /// @notice Last price update for `asset` was before the accepted stale price threshold
    error ChainlinkUsdOracle_StalePrice(address asset);
    /// @notice Latest price update for `asset` has a negative value
    error ChainlinkUsdOracle_NonPositivePrice(address asset);
    /// @notice Invalid oracle update round
    error ChainlinkUsdOracle_InvalidRound();
    /// @notice Missing price feed
    error ChainlinkUsdOracle_MissingPriceFeed(address asset);

    /// @param owner Oracle owner address
    /// @param arbSeqFeed Chainlink arbitrum sequencer feed
    /// @param ethUsdFeed Chainlink ETH/USD price feed
    /// @param ethUsdThreshold Stale price threshold for ETH/USD feed
    constructor(address owner, address arbSeqFeed, address ethUsdFeed, uint256 ethUsdThreshold) Ownable() {
        ARB_SEQ_FEED = IAggregatorV3(arbSeqFeed);

        PriceFeed memory feed = PriceFeed({
            feed: ethUsdFeed,
            feedDecimals: IAggregatorV3(ethUsdFeed).decimals(),
            assetDecimals: 18,
            stalePriceThreshold: ethUsdThreshold
        });
        priceFeedFor[ETH] = feed;
        emit FeedSet(ETH, feed);

        _transferOwnership(owner);
    }

    /// @notice Compute the equivalent ETH value for a given amount of a particular asset
    /// @param asset Address of the asset to be priced
    /// @param amt Amount of the given asset to be priced
    function getValueInEth(address asset, uint256 amt) external view returns (uint256) {
        _checkSequencerFeed();
        PriceFeed storage priceFeed = priceFeedFor[asset];

        // fetch asset/usd and eth/usd price scaled to 18 decimals
        uint256 assetUsdPrice = _getPriceWithSanityChecks(asset, priceFeed);
        uint256 ethUsdPrice = _getPriceWithSanityChecks(ETH, priceFeedFor[ETH]);

        // scale amt to 18 decimals
        uint256 scaledAmt;
        uint256 assetDecimals = priceFeed.assetDecimals;
        if (assetDecimals <= 18) scaledAmt = amt * (10 ** (18 - assetDecimals));
        else scaledAmt = amt / (10 ** (assetDecimals - 18));

        return scaledAmt.mulDiv(assetUsdPrice, ethUsdPrice);
    }

    /// @notice Set Chainlink ETH-denominated feed for an asset
    /// @param asset Address of asset to be priced
    /// @param feed Address of the asset/eth chainlink feed
    /// @param stalePriceThreshold prices older than this duration are considered invalid, denominated in seconds
    /// @dev stalePriceThreshold must be equal or greater to the feed's heartbeat
    function setFeed(address asset, address feed, uint256 stalePriceThreshold) external onlyOwner {
        PriceFeed memory feedData = PriceFeed({
            feed: feed,
            feedDecimals: IAggregatorV3(feed).decimals(),
            assetDecimals: IERC20Metadata(asset).decimals(),
            stalePriceThreshold: stalePriceThreshold
        });
        priceFeedFor[asset] = feedData;
        emit FeedSet(asset, feedData);
    }

    /// @dev Check L2 sequencer health
    function _checkSequencerFeed() private view {
        (, int256 answer, uint256 startedAt,,) = ARB_SEQ_FEED.latestRoundData();

        // answer == 0 -> sequncer up
        // answer == 1 -> sequencer down
        if (answer != 0) revert ChainlinkUsdOracle_SequencerDown();
        if (startedAt == 0) revert ChainlinkUsdOracle_InvalidRound();

        if (block.timestamp - startedAt <= SEQ_GRACE_PERIOD) revert ChainlinkUsdOracle_GracePeriodNotOver();
    }

    /// @dev Fetch price from chainlink feed with sanity checks
    function _getPriceWithSanityChecks(address asset, PriceFeed storage priceFeed) private view returns (uint256) {
        // check if feed exists
        address feed = priceFeed.feed;
        if (feed == address(0)) revert ChainlinkUsdOracle_MissingPriceFeed(asset);

        // fetch price with checks
        (, int256 price,, uint256 updatedAt,) = IAggregatorV3(feed).latestRoundData();
        if (price <= 0) revert ChainlinkUsdOracle_NonPositivePrice(asset);
        if (updatedAt < block.timestamp - priceFeed.stalePriceThreshold) revert ChainlinkUsdOracle_StalePrice(asset);

        // scale price to 18 decimals
        uint256 feedDecimals = priceFeed.feedDecimals;
        if (feedDecimals <= 18) return uint256(price) * (10 ** (18 - feedDecimals));
        else return uint256(price) / (10 ** (feedDecimals - 18));
    }
}
