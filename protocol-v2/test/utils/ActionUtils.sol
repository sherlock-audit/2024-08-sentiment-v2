// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Action, Operation } from "src/PositionManager.sol";

library ActionUtils {
    function newPosition(address owner, bytes32 salt) internal pure returns (Action memory) {
        bytes memory data = abi.encodePacked(owner, salt);
        Action memory action = Action({ op: Operation.NewPosition, data: data });
        return action;
    }

    function deposit(address asset, uint256 amt) internal pure returns (Action memory) {
        bytes memory data = abi.encodePacked(asset, amt);
        Action memory action = Action({ op: Operation.Deposit, data: data });
        return action;
    }

    function addToken(address asset) internal pure returns (Action memory) {
        bytes memory data = abi.encodePacked(asset);
        Action memory action = Action({ op: Operation.AddToken, data: data });
        return action;
    }

    function removeToken(address asset) internal pure returns (Action memory) {
        bytes memory data = abi.encodePacked(asset);
        Action memory action = Action({ op: Operation.RemoveToken, data: data });
        return action;
    }

    function borrow(uint256 poolId, uint256 amt) internal pure returns (Action memory) {
        bytes memory data = abi.encodePacked(poolId, amt);
        Action memory action = Action({ op: Operation.Borrow, data: data });
        return action;
    }

    function approve(address spender, address asset, uint256 amt) internal pure returns (Action memory) {
        bytes memory data = abi.encodePacked(spender, asset, amt);
        Action memory action = Action({ op: Operation.Approve, data: data });
        return action;
    }

    function transfer(address recipient, address asset, uint256 amt) internal pure returns (Action memory) {
        bytes memory data = abi.encodePacked(recipient, asset, amt);
        Action memory action = Action({ op: Operation.Transfer, data: data });
        return action;
    }
}
