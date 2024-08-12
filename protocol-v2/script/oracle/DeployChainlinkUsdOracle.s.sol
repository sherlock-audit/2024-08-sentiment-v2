// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseScript.s.sol";
import { console2 } from "forge-std/console2.sol";
import { ChainlinkUsdOracle } from "src/oracle/ChainlinkUsdOracle.sol";

contract DeployChainlinkUsdOracle is BaseScript {
    address owner;
    address ethUsdFeed;
    address arbSeqFeed;
    uint256 ethUsdThreshold;
    ChainlinkUsdOracle oracle;

    function run() public {
        getParams();

        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        oracle = new ChainlinkUsdOracle(owner, arbSeqFeed, ethUsdFeed, ethUsdThreshold);
        console2.log("ChainlinkUsdOracle: ", address(oracle));
    }

    function getParams() internal {
        string memory config = getConfig();

        owner = vm.parseJsonAddress(config, "$.DeployChainlinkUsdOracle.owner");
        arbSeqFeed = vm.parseJsonAddress(config, "$.DeployChainLinkUsdOracle.arbSeqFeed");
        ethUsdFeed = vm.parseJsonAddress(config, "$.DeployChainlinkUsdOracle.ethUsdFeed");
        ethUsdThreshold = vm.parseJsonUint(config, "$.DeployChainlinkUsdOracle.ethUsdFeed");
    }
}
