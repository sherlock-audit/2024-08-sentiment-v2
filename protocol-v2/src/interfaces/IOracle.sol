// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                            IOracle
//////////////////////////////////////////////////////////////*/

/// @title IOracle
/// @notice Common interface for all oracle implementations
interface IOracle {
    /// @notice Compute the equivalent ETH value for a given amount of a particular asset
    /// @param asset Address of the asset to be priced
    /// @param amt Amount of the given asset to be priced
    /// @return valueInEth Equivalent ETH value for the given asset and amount, scaled by 18 decimals
    function getValueInEth(address asset, uint256 amt) external view returns (uint256 valueInEth);
}
