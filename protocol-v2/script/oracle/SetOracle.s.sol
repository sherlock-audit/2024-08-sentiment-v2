// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseScript.s.sol";
import { console2 } from "forge-std/console2.sol";
import { RiskEngine } from "src/RiskEngine.sol";

contract SetOracle is BaseScript {
    address asset;
    address oracle;
    RiskEngine riskEngine;

    function run() public {
        getParams();

        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        riskEngine.setOracle(asset, oracle);
        console2.log("SetOracle: ", asset, oracle);
    }

    function getParams() internal {
        string memory config = getConfig();

        asset = vm.parseJsonAddress(config, "$.SetOracle.asset");
        oracle = vm.parseJsonAddress(config, "$.SetOracle.oracle");
        riskEngine = RiskEngine(vm.parseJsonAddress(config, "$.SetOracle.riskEngine"));
    }
}
