// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IRateModel } from "../interfaces/IRateModel.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title KinkedRateModel
/// @notice Piecewise linear rate model implementation
contract KinkedRateModel is IRateModel {
    using Math for uint256;

    /// @notice Number of seconds in a year as per the rate model
    uint256 public constant SECONDS_PER_YEAR = 31_557_600; // 1 year = 365.25 days

    /// @notice Minimum interest rate
    uint256 public immutable MIN_RATE_1;

    /// @notice Interest slope before optimal utilisation
    uint256 public immutable SLOPE_1;

    /// @notice Interest slope after optimal utilisation
    uint256 public immutable SLOPE_2;

    /// @notice Optimal utilisation
    uint256 public immutable OPTIMAL_UTIL; // 1e18 = 100%

    uint256 private immutable MIN_RATE_2; // MIN_RATE_1 + SLOPE_1
    uint256 private immutable MAX_EXCESS_UTIL; // 1e18 - OPTIMAL_UTIL

    constructor(uint256 minRate, uint256 slope1, uint256 slope2, uint256 optimalUtil) {
        assert(optimalUtil < 1e18); // optimal utilisation < 100%

        MIN_RATE_1 = minRate;
        SLOPE_1 = slope1;
        SLOPE_2 = slope2;
        OPTIMAL_UTIL = optimalUtil;
        MIN_RATE_2 = MIN_RATE_1 + SLOPE_1;
        MAX_EXCESS_UTIL = 1e18 - optimalUtil;
    }

    /// @notice Compute the amount of interest accrued since the last interest update
    function getInterestAccrued(
        uint256 lastUpdated,
        uint256 totalBorrows,
        uint256 totalAssets
    ) external view returns (uint256) {
        uint256 rateFactor = ((block.timestamp - lastUpdated)).mulDiv(
            getInterestRate(totalBorrows, totalAssets), SECONDS_PER_YEAR, Math.Rounding.Up
        ); // rateFactor = time delta * apr / secs_per_year

        return totalBorrows.mulDiv(rateFactor, 1e18, Math.Rounding.Up); // interestAccrued = borrows * rateFactor
    }

    /// @notice Fetch the instantaneous borrow interest rate for a given pool state
    function getInterestRate(uint256 totalBorrows, uint256 totalAssets) public view returns (uint256) {
        uint256 util = (totalAssets == 0) ? 0 : totalBorrows.mulDiv(1e18, totalAssets, Math.Rounding.Up);

        if (util <= OPTIMAL_UTIL) return MIN_RATE_1 + SLOPE_1.mulDiv(util, OPTIMAL_UTIL, Math.Rounding.Down);
        else return MIN_RATE_2 + SLOPE_2.mulDiv((util - OPTIMAL_UTIL), MAX_EXCESS_UTIL, Math.Rounding.Down);
    }
}
