// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { BaseScript } from "../BaseScript.s.sol";
import { console2 } from "forge-std/console2.sol";

import { IERC20 } from "forge-std/interfaces/IERC20.sol";
import { Pool } from "src/Pool.sol";

contract InitializePool is BaseScript {
    address pool;
    address owner;
    address asset;
    bytes32 rateModelKey;
    uint256 borrowCap;
    uint256 depositCap;
    uint256 initialDepositAmt;

    function run() public {
        getParams();
        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        IERC20(asset).approve(pool, initialDepositAmt);
        uint256 poolId = Pool(pool).initializePool(owner, asset, rateModelKey, depositCap, borrowCap, initialDepositAmt);
        console2.log("poolId: ", poolId);
    }

    function getParams() internal {
        string memory config = getConfig();
        pool = vm.parseJsonAddress(config, "$.InitializePool.pool");
        owner = vm.parseJsonAddress(config, "$.InitializePool.owner");
        asset = vm.parseJsonAddress(config, "$.InitializePool.asset");
        rateModelKey = vm.parseJsonBytes32(config, "$.InitializePool.rateModelKey");
        borrowCap = vm.parseJsonUint(config, "$.InitializePool.borrowCap");
        depositCap = vm.parseJsonUint(config, "$.InitializePool.depositCap");
        initialDepositAmt = (vm.parseJsonUint(config, "$.InitializePool.initialDepositAmt"));
    }
}
