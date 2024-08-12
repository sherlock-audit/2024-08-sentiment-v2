// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                        ChainlinkUsdOracle
//////////////////////////////////////////////////////////////*/

import { IOracle } from "../interfaces/IOracle.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

interface IAggegregatorV3 {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    function decimals() external view returns (uint256);
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
    IAggegregatorV3 public immutable ARB_SEQ_FEED;

    /// @notice Chainlink ETH/USD price feed
    IAggegregatorV3 public immutable ETH_USD_FEED;

    /// @notice Fetch the ETH-denominated price feed associated with a given asset
    /// @dev returns address(0) if there is no associated feed
    mapping(address asset => address feed) public priceFeedFor;

    /// @notice Prices older than the stale price threshold are considered invalid
    mapping(address feed => uint256 stalePriceThreshold) public stalePriceThresholdFor;

    /// @notice New Usd-denomiated chainlink feed has been associated with an asset
    event FeedSet(address indexed asset, address feed);

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

    /// @param owner Oracle owner address
    /// @param arbSeqFeed Chainlink arbitrum sequencer feed
    /// @param ethUsdFeed Chainlink ETH/USD price feed
    /// @param ethUsdThreshold Stale price threshold for ETH/USD feed
    constructor(address owner, address arbSeqFeed, address ethUsdFeed, uint256 ethUsdThreshold) Ownable() {
        ARB_SEQ_FEED = IAggegregatorV3(arbSeqFeed);
        ETH_USD_FEED = IAggegregatorV3(ethUsdFeed);
        priceFeedFor[ETH] = ethUsdFeed;
        stalePriceThresholdFor[ETH] = ethUsdThreshold;

        _transferOwnership(owner);
    }

    /// @notice Compute the equivalent ETH value for a given amount of a particular asset
    /// @param asset Address of the asset to be priced
    /// @param amt Amount of the given asset to be priced
    function getValueInEth(address asset, uint256 amt) external view returns (uint256) {
        _checkSequencerFeed();

        uint256 ethUsdPrice = _getPriceWithSanityChecks(ETH);
        uint256 assetUsdPrice = _getPriceWithSanityChecks(asset);

        uint256 decimals = IERC20Metadata(asset).decimals();

        // [ROUND] price is rounded down. this is used for both debt and asset math, no effect
        if (decimals <= 18) return (amt * 10 ** (18 - decimals)).mulDiv(uint256(assetUsdPrice), uint256(ethUsdPrice));
        else return (amt / (10 ** decimals - 18)).mulDiv(uint256(assetUsdPrice), uint256(ethUsdPrice));
    }

    /// @notice Set Chainlink ETH-denominated feed for an asset
    /// @param asset Address of asset to be priced
    /// @param feed Address of the asset/eth chainlink feed
    /// @param stalePriceThreshold prices older than this duration are considered invalid, denominated in seconds
    /// @dev stalePriceThreshold must be equal or greater to the feed's heartbeat
    function setFeed(address asset, address feed, uint256 stalePriceThreshold) external onlyOwner {
        assert(IAggegregatorV3(feed).decimals() == 8);
        priceFeedFor[asset] = feed;
        stalePriceThresholdFor[feed] = stalePriceThreshold;
        emit FeedSet(asset, feed);
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
    function _getPriceWithSanityChecks(address asset) private view returns (uint256) {
        address feed = priceFeedFor[asset];
        (, int256 price,, uint256 updatedAt,) = IAggegregatorV3(feed).latestRoundData();
        if (price <= 0) revert ChainlinkUsdOracle_NonPositivePrice(asset);
        if (updatedAt < block.timestamp - stalePriceThresholdFor[feed]) revert ChainlinkUsdOracle_StalePrice(asset);
        return uint256(price);
    }
}
