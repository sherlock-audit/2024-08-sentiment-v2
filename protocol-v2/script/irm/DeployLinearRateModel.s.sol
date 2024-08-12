// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseScript.s.sol";
import { console2 } from "forge-std/console2.sol";
import { LinearRateModel } from "src/irm/LinearRateModel.sol";

contract DeployLinearRateModel is BaseScript {
    uint256 minRate;
    uint256 maxRate;
    LinearRateModel rateModel;

    function run() public {
        getParams();
        require(maxRate > minRate, "MAX <= MIN");

        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        rateModel = new LinearRateModel(minRate, maxRate);
        console2.log("LinearRateModel: ", address(rateModel));
    }

    function getParams() internal {
        string memory config = getConfig();

        minRate = vm.parseJsonUint(config, "$.DeployLinearRateModel.minRate");
        maxRate = vm.parseJsonUint(config, "$.DeployLinearRateModel.maxRate");
    }
}
