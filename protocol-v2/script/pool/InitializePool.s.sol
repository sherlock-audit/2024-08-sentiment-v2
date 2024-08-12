// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { BaseScript } from "../BaseScript.s.sol";
import { console2 } from "forge-std/console2.sol";
import { Pool } from "src/Pool.sol";

contract InitializePool is BaseScript {
    address pool;

    address owner;
    address asset;
    bytes32 rateModelKey;
    uint128 interestFee;
    uint128 originationFee;
    uint128 poolCap;

    function run() public {
        getParams();

        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        uint256 poolId = Pool(pool).initializePool(owner, asset, poolCap, rateModelKey);
        console2.log("poolId: ", poolId);
    }

    function getParams() internal {
        string memory config = getConfig();

        pool = vm.parseJsonAddress(config, "$.InitializePool.pool");
        owner = vm.parseJsonAddress(config, "$.InitializePool.owner");
        asset = vm.parseJsonAddress(config, "$.InitializePool.asset");
        rateModelKey = vm.parseJsonBytes32(config, "$.InitializePool.rateModelKey");
        interestFee = uint128(vm.parseJsonUint(config, "$.InitializePool.interestFee"));
        originationFee = uint128(vm.parseJsonUint(config, "$.InitializePool.originationFee"));
        poolCap = uint128(vm.parseJsonUint(config, "$.InitializePool.poolCap"));
    }
}
