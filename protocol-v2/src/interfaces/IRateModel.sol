// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                            IRateModel
//////////////////////////////////////////////////////////////*/

/// @title IRateModel
/// @notice Common interface for all rate model implementations
interface IRateModel {
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
    ) external view returns (uint256 interestAccrued);

    /// @notice Fetch the instantaneous borrow interest rate for a given pool state
    /// @param totalBorrows Total amount of assets borrowed from the pool
    /// @param totalAssets Total amount of assets controlled by the pool
    /// @return interestRate Instantaneous interest rate for the given pool state, scaled by 18 decimals
    function getInterestRate(uint256 totalBorrows, uint256 totalAssets) external view returns (uint256 interestRate);
}
