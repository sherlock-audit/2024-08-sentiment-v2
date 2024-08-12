// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                        LinearRateModel
//////////////////////////////////////////////////////////////*/

import { IRateModel } from "../interfaces/IRateModel.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title LinearRateModel
/// @notice Rate model implementation with a bounded linear rate curve
contract LinearRateModel is IRateModel {
    using Math for uint256;

    /// @notice Number of seconds in a year as per the rate model
    uint256 public constant SECONDS_PER_YEAR = 31_557_600; // 1 year = 365.25 days

    /// @notice Minimum interest rate bound scaled to 18 decimals
    uint256 public immutable MIN_RATE;

    /// @notice Maximum interest rate bound scaled to 18 decimals
    uint256 public immutable MAX_RATE;

    /// @dev Internal utility constant equivalent to MAX_RATE - MIN_RATE
    uint256 internal immutable RATE_DIFF;

    /// @param minRate Minimum interest rate bound scaled to 18 decimals
    /// @param maxRate Maximum interest rate bound scaled to 18 decimals
    constructor(uint256 minRate, uint256 maxRate) {
        assert(maxRate > minRate);

        MIN_RATE = minRate;
        MAX_RATE = maxRate;
        RATE_DIFF = maxRate - minRate;
    }

    /// @notice Compute the amount of interest accrued since the last interest update
    /// @param lastUpdated Timestamp of the last interest update
    /// @param totalBorrows Total amount of assets borrowed from the pool
    /// @param totalAssets Total amount of assets controlled by the pool
    /// @return interestAccrued Amount of interest accrued since the last interest update
    ///         denominated in terms of the given asset
    function getInterestAccrued(
        uint256 lastUpdated,
        uint256 totalBorrows,
        uint256 totalAssets
    ) external view returns (uint256) {
        // [ROUND] rateFactor is rounded up, in favor of the protocol
        // rateFactor = time delta * apr / secs_per_year
        uint256 rateFactor = ((block.timestamp - lastUpdated)).mulDiv(
            getInterestRate(totalBorrows, totalAssets), SECONDS_PER_YEAR, Math.Rounding.Up
        );

        // [ROUND] interest accrued is rounded up, in favor of the protocol
        // interestAccrued = borrows * rateFactor
        return totalBorrows.mulDiv(rateFactor, 1e18, Math.Rounding.Up);
    }

    /// @notice Fetch the instantaneous borrow interest rate for a given pool state
    /// @param totalBorrows Total amount of assets borrowed from the pool
    /// @param totalAssets Total amount of assets controlled by the pool
    /// @return interestRate Instantaneous interest rate for the given pool state, scaled by 18 decimals
    function getInterestRate(uint256 totalBorrows, uint256 totalAssets) public view returns (uint256) {
        // [ROUND] pool utilisation is rounded up, in favor of the protocol
        // util = totalBorrows / (totalBorrows + idleAssetAmt)
        uint256 util = (totalAssets == 0) ? 0 : totalBorrows.mulDiv(1e18, totalAssets, Math.Rounding.Up);

        // [ROUND] interest rate is rounded up, in favor of the protocol
        // interest rate = MIN_RATE + util * (MAX_RATE - MIN_RATE)
        return MIN_RATE + util.mulDiv(RATE_DIFF, 1e18, Math.Rounding.Up);
    }
}
