// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

contract BaseScript is Script {
    function getConfig() public view returns (string memory) {
        string memory path =
            string.concat(vm.projectRoot(), "/config/", vm.toString(block.chainid), "/", vm.envString("SCRIPT_CONFIG"));
        return vm.readFile(path);
    }

    function getLogPathBase() public view returns (string memory) {
        return string.concat(vm.projectRoot(), "/script/logs/");
    }
}
