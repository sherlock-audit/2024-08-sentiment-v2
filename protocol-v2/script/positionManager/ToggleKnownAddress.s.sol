// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { BaseScript } from "../BaseScript.s.sol";
import { console2 } from "forge-std/console2.sol";
import { PositionManager } from "src/PositionManager.sol";

contract ToggleKnownAsset is BaseScript {
    address target;
    address positionManager;

    function run() public {
        getParams();

        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        PositionManager(positionManager).toggleKnownAsset(target);
        console2.log("ToggleKnownAddress: ", target);
    }

    function getParams() internal {
        string memory config = getConfig();

        target = vm.parseJsonAddress(config, "$.ToggleKnownAddress.target");
        positionManager = vm.parseJsonAddress(config, "$.ToggleKnownAddress.positionManager");
    }
}
