// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { BaseTest } from "../BaseTest.t.sol";
import { console2 } from "forge-std/console2.sol";

contract RegistryTest is BaseTest {
    // keccak(SENTIMENT_POSITION_MANAGER_KEY)
    bytes32 public constant SENTIMENT_POSITION_MANAGER_KEY =
        0xd4927490fbcbcafca716cca8e8c8b7d19cda785679d224b14f15ce2a9a93e148;
    // keccak(SENTIMENT_POOL_KEY)
    bytes32 public constant SENTIMENT_POOL_KEY = 0x1a99cbf6006db18a0e08427ff11db78f3ea1054bc5b9d48122aae8d206c09728;
    // keccak(SENTIMENT_RISK_ENGINE_KEY)
    bytes32 public constant SENTIMENT_RISK_ENGINE_KEY =
        0x5b6696788621a5d6b5e3b02a69896b9dd824ebf1631584f038a393c29b6d7555;
    // keccak(SENIMENT_POSITION_BEACON_KEY)
    bytes32 public constant SENTIMENT_POSITION_BEACON_KEY =
        0x6e7384c78b0e09fb848f35d00a7b14fc1ad10ae9b10117368146c0e09b6f2fa2;
    // keccak(SENTIMENT_RISK_MODULE_KEY)
    bytes32 public constant SENTIMENT_RISK_MODULE_KEY =
        0x881469d14b8443f6c918bdd0a641e9d7cae2592dc28a4f922a2c4d7ca3d19c77;

    function setUp() public override {
        super.setUp();
    }

    function testInitializesRegistryCorrectly() public view {
        assertEq(address(protocol.pool()), protocol.registry().addressFor(SENTIMENT_POOL_KEY));
        assertEq(address(protocol.riskEngine()), protocol.registry().addressFor(SENTIMENT_RISK_ENGINE_KEY));
        assertEq(address(protocol.positionManager()), protocol.registry().addressFor(SENTIMENT_POSITION_MANAGER_KEY));
        assertEq(address(protocol.positionBeacon()), protocol.registry().addressFor(SENTIMENT_POSITION_BEACON_KEY));
        assertEq(address(protocol.riskModule()), protocol.registry().addressFor(SENTIMENT_RISK_MODULE_KEY));
    }
}
