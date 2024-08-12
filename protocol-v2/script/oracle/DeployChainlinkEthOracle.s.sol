// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseScript.s.sol";
import { console2 } from "forge-std/console2.sol";
import { ChainlinkEthOracle } from "src/oracle/ChainlinkEthOracle.sol";

contract DeployChainlinkEthOracle is BaseScript {
    address owner;
    address arbSeqFeed;
    ChainlinkEthOracle oracle;

    function run() public {
        getParams();

        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        oracle = new ChainlinkEthOracle(owner, arbSeqFeed);
        console2.log("ChainlinkEthOracle: ", address(oracle));
    }

    function getParams() internal {
        string memory config = getConfig();

        owner = vm.parseJsonAddress(config, "$.DeployChainLinkEthOracle.owner");
        arbSeqFeed = vm.parseJsonAddress(config, "$.DeployChainLinkEthOracle.arbSeqFeed");
    }
}
