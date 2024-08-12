// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { MockERC20 } from "./MockERC20.sol";

// 1:1 swap for any token
contract MockSwap {
    function swap(address inToken, address outToken, uint256 inAmount) public {
        MockERC20(inToken).transferFrom(msg.sender, address(this), inAmount);
        MockERC20(outToken).mint(msg.sender, inAmount);
    }
}
