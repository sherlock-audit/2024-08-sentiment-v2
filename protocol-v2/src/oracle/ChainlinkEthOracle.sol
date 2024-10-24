// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                        ChainlinkEthOracle
//////////////////////////////////////////////////////////////*/

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

/// @title ChainlinkEthOracle
/// @notice Oracle implementation to price assets using ETH-denominated chainlink feeds
contract ChainlinkEthOracle is Ownable, IOracle {
    using Math for uint256;

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

    /// @notice Fetch configured feed data for a given asset
    mapping(address asset => PriceFeed feed) public priceFeedFor;

    /// @notice An Eth-denomiated chainlink feed has been associated with an asset
    event FeedSet(address indexed asset, PriceFeed feedData);

    /// @notice L2 sequencer is experiencing downtime
    error ChainlinkEthOracle_SequencerDown();
    /// @notice L2 Sequencer has recently recovered from downtime and is in its grace period
    error ChainlinkEthOracle_GracePeriodNotOver();
    /// @notice Last price update for `asset` was before the accepted stale price threshold
    error ChainlinkEthOracle_StalePrice(address asset);
    /// @notice Latest price update for `asset` has a negative value
    error ChainlinkEthOracle_NonPositivePrice(address asset);
    /// @notice Invalid oracle update round
    error ChainlinkEthOracle_InvalidRound();
    /// @notice Missing price feed
    error ChainlinkEthOracle_MissingPriceFeed(address asset);

    /// @param owner Oracle owner address
    /// @param arbSeqFeed Chainlink arbitrum sequencer feed
    constructor(address owner, address arbSeqFeed) Ownable() {
        ARB_SEQ_FEED = IAggregatorV3(arbSeqFeed);

        _transferOwnership(owner);
    }

    /// @notice Compute the equivalent ETH value for a given amount of a particular asset
    /// @param asset Address of the asset to be priced
    /// @param amt Amount of the given asset to be priced
    function getValueInEth(address asset, uint256 amt) external view returns (uint256) {
        _checkSequencerFeed();

        PriceFeed storage priceFeed = priceFeedFor[asset];
        // [ROUND] price is rounded down. this is used for both debt and asset math, neutral effect.
        return amt.mulDiv(_getPriceWithSanityChecks(asset, priceFeed), priceFeed.assetDecimals);
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
        if (answer != 0) revert ChainlinkEthOracle_SequencerDown();
        if (startedAt == 0) revert ChainlinkEthOracle_InvalidRound();

        if (block.timestamp - startedAt <= SEQ_GRACE_PERIOD) revert ChainlinkEthOracle_GracePeriodNotOver();
    }

    /// @dev Fetch price from chainlink feed with sanity checks
    function _getPriceWithSanityChecks(address asset, PriceFeed storage priceFeed) private view returns (uint256) {
        // check if feed exists
        address feed = priceFeed.feed;
        if (feed == address(0)) revert ChainlinkEthOracle_MissingPriceFeed(asset);

        // fetch price with checks
        (, int256 price,, uint256 updatedAt,) = IAggregatorV3(feed).latestRoundData();
        if (price <= 0) revert ChainlinkEthOracle_NonPositivePrice(asset);
        if (updatedAt < block.timestamp - priceFeed.stalePriceThreshold) revert ChainlinkEthOracle_StalePrice(asset);

        // scale price to 18 decimals
        uint256 feedDecimals = priceFeed.feedDecimals;
        if (feedDecimals <= 18) return uint256(price) * (10 ** (18 - feedDecimals));
        else return uint256(price) / (10 ** (feedDecimals - 18));
    }
}
