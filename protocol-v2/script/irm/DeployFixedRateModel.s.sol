// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseScript.s.sol";
import { console2 } from "forge-std/console2.sol";
import { FixedRateModel } from "src/irm/FixedRateModel.sol";

contract DeployFixedRateModel is BaseScript {
    uint256 rate;
    FixedRateModel rateModel;

    function run() public {
        getParams();

        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        rateModel = new FixedRateModel(rate);
        console2.log("FixedRateModel: ", address(rateModel));
    }

    function getParams() internal {
        string memory config = getConfig();

        rate = vm.parseJsonUint(config, "$.DeployFixedRateModel.rate");
    }
}
