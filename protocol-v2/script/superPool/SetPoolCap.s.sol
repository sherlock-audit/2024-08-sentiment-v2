// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { BaseScript } from "../BaseScript.s.sol";
import { console2 } from "forge-std/console2.sol";
import { SuperPool } from "src/SuperPool.sol";

contract SetPoolCap is BaseScript {
    uint256 poolId;
    uint256 poolCap;
    SuperPool superPool;

    function run() public {
        getParams();

        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        superPool.addPool(poolId, poolCap);
        console2.log("SetPoolCap: ", address(superPool), poolId, poolCap);
    }

    function getParams() internal {
        string memory config = getConfig();

        poolId = vm.parseJsonUint(config, "$.SetPoolCap.poolId");
        poolCap = vm.parseJsonUint(config, "$.SetPoolCap.poolCap");
        superPool = SuperPool(vm.parseJsonAddress(config, "$.SetPoolCap.superPool"));
    }
}
