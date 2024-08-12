// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseScript.s.sol";
import { console2 } from "forge-std/console2.sol";
import { ChainlinkUsdOracle } from "src/oracle/ChainlinkUsdOracle.sol";

contract SetClUsdFeed is BaseScript {
    address feed;
    address asset;
    uint256 stalePriceThreshold;
    ChainlinkUsdOracle oracle;

    function run() public {
        getParams();

        vm.broadcast(vm.envUint("PRIVATE_KEY"));
        oracle.setFeed(asset, feed, stalePriceThreshold);
        console2.log("SetClUsdFeed: ", asset, feed, stalePriceThreshold);
    }

    function getParams() internal {
        string memory config = getConfig();

        feed = vm.parseJsonAddress(config, "$.SetClUsdFeed.feed");
        asset = vm.parseJsonAddress(config, "$.SetClUsdFeed.asset");
        oracle = ChainlinkUsdOracle(vm.parseJsonAddress(config, "$.SetClUsdFeed.oracle"));
        stalePriceThreshold = vm.parseJsonUint(config, "$.SetClEthFeed.stalePriceThreshold");
    }
}
