// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                        FixedPriceOracle
//////////////////////////////////////////////////////////////*/

import { IOracle } from "../interfaces/IOracle.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title FixedPriceOracle
/// @notice Oracle implementation for fixed price assets
contract FixedPriceOracle is IOracle {
    using Math for uint256;

    /// @notice Fixed price of the asset in ETH terms scaled to 18 decimals
    uint256 public immutable PRICE;

    /// @param price Fixed price of the asset in ETH terms scaled to 18 decimals
    constructor(uint256 price) {
        PRICE = price;
    }

    /// @notice Compute the equivalent ETH value for a given amount of a particular asset
    /// @param asset Address of the asset to be priced
    /// @param amt Amount of the given asset to be priced
    /// @return valueInEth Equivalent ETH value for the given asset and amount, scaled by 18 decimals
    function getValueInEth(address asset, uint256 amt) external view returns (uint256) {
        // [ROUND] price is rounded down. this is used for both debt and asset math, neutral effect
        // value = amt * price % asset.decimals()
        return amt.mulDiv(PRICE, (10 ** IERC20Metadata(asset).decimals()));
    }
}
