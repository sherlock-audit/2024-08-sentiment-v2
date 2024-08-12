// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseScript.s.sol";
import { console2 } from "forge-std/console2.sol";
import { FixedPriceOracle } from "src/oracle/FixedPriceOracle.sol";

contract DeployFixedPriceOracle is BaseScript {
    uint256 price;
    FixedPriceOracle oracle;

    function run() public {
        getParams();

        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        oracle = new FixedPriceOracle(price);
        console2.log("FixedPriceOracle: ", address(oracle));
    }

    function getParams() internal {
        price = vm.parseJsonUint(getConfig(), "$.DeployFixedPriceOracle.price");
    }
}
