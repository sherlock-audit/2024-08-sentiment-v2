// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseScript.s.sol";
import { console2 } from "forge-std/console2.sol";
import { PortfolioLens } from "src/lens/PortfolioLens.sol";
import { SuperPoolLens } from "src/lens/SuperPoolLens.sol";

contract DeployLens is BaseScript {
    address pool;
    address riskEngine;
    address positionManager;
    PortfolioLens portfolioLens;
    SuperPoolLens superPoolLens;

    function run() public {
        getParams();

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        superPoolLens = new SuperPoolLens(pool, riskEngine);
        portfolioLens = new PortfolioLens(pool, riskEngine, positionManager);
        vm.stopBroadcast();
        console2.log("SuperPoolLens: ", address(superPoolLens));
        console2.log("PortfolioLens: ", address(portfolioLens));
    }

    function getParams() internal {
        string memory config = getConfig();

        pool = vm.parseJsonAddress(config, "$.DeployLens.pool");
        riskEngine = vm.parseJsonAddress(config, "$.DeployLens.riskEngine");
        positionManager = vm.parseJsonAddress(config, "$.DeployLens.positionManager");
    }
}
