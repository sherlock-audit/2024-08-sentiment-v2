// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { FixedRateModel } from "../../src/irm/FixedRateModel.sol";
import { LinearRateModel } from "../../src/irm/LinearRateModel.sol";
import "../BaseTest.t.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { Action, Operation } from "src/PositionManager.sol";
import { RiskEngine } from "src/RiskEngine.sol";
import { FixedPriceOracle } from "src/oracle/FixedPriceOracle.sol";

contract RiskEngineUnitTests is BaseTest {
    Pool pool;
    address position;
    Registry registry;
    RiskEngine riskEngine;
    address positionOwner = makeAddr("positionOwner");
    FixedPriceOracle asset1Oracle = new FixedPriceOracle(10e18);
    FixedPriceOracle asset2Oracle = new FixedPriceOracle(0.5e18);

    function setUp() public override {
        super.setUp();

        pool = protocol.pool();
        registry = protocol.registry();
        riskEngine = protocol.riskEngine();

        vm.startPrank(protocolOwner);
        riskEngine.setOracle(address(asset1), address(asset1Oracle));
        riskEngine.setOracle(address(asset2), address(asset2Oracle));
        vm.stopPrank();

        asset1.mint(address(this), 10_000 ether);
        asset1.approve(address(pool), 10_000 ether);

        pool.deposit(linearRatePool, 10_000 ether, address(0x9));
    }

    function testRiskEngineInit() public {
        RiskEngine testRiskEngine = new RiskEngine(address(registry), 0.2e18, 0.8e18);
        assertEq(address(testRiskEngine.REGISTRY()), address(registry));
        assertEq(testRiskEngine.minLtv(), 0.2e18);
        assertEq(testRiskEngine.maxLtv(), 0.8e18);
    }

    function testNoOracleFound(address asset) public {
        vm.assume(asset != address(asset1) && asset != address(asset2));
        vm.expectRevert(abi.encodeWithSelector(RiskEngine.RiskEngine_NoOracleFound.selector, asset));
        riskEngine.getOracleFor(asset);
    }

    function testOwnerCanUpdateLTV() public {
        uint256 startLtv = riskEngine.ltvFor(linearRatePool, address(asset1));
        assertEq(startLtv, 0);

        vm.startPrank(poolOwner);
        riskEngine.requestLtvUpdate(linearRatePool, address(asset2), 0.75e18);

        riskEngine.acceptLtvUpdate(linearRatePool, address(asset2));

        assertEq(riskEngine.ltvFor(linearRatePool, address(asset2)), 0.75e18);
    }

    function testOnlyOwnerCanUpdateLTV(address sender) public {
        vm.assume(sender != poolOwner);

        vm.startPrank(sender);
        vm.expectRevert(abi.encodeWithSelector(RiskEngine.RiskEngine_OnlyPoolOwner.selector, linearRatePool, sender));
        riskEngine.requestLtvUpdate(linearRatePool, address(asset1), 0.75e18);
    }

    function testCannotUpdateLTVForUnknownAsset(address asset, uint256 ltv) public {
        vm.assume(asset != address(asset1) && asset != address(asset2));

        vm.prank(poolOwner);
        vm.expectRevert(abi.encodeWithSelector(RiskEngine.RiskEngine_NoOracleFound.selector, asset));
        riskEngine.requestLtvUpdate(linearRatePool, asset, ltv);
    }

    function testOwnerCanRejectLTVUpdated() public {
        // Set a starting non-zero ltv
        vm.startPrank(poolOwner);
        riskEngine.requestLtvUpdate(linearRatePool, address(asset2), 0.75e18);
        riskEngine.acceptLtvUpdate(linearRatePool, address(asset2));

        assertEq(riskEngine.ltvFor(linearRatePool, address(asset2)), 0.75e18);

        riskEngine.requestLtvUpdate(linearRatePool, address(asset2), 0.5e18);
        riskEngine.rejectLtvUpdate(linearRatePool, address(asset2));

        assertEq(riskEngine.ltvFor(linearRatePool, address(asset2)), 0.75e18);
    }

    function testNoLTVUpdate(address asset) public {
        vm.prank(poolOwner);
        vm.expectRevert(abi.encodeWithSelector(RiskEngine.RiskEngine_NoLtvUpdate.selector, linearRatePool, asset));
        riskEngine.acceptLtvUpdate(linearRatePool, asset);
    }

    function testNonOwnerCannotUpdateLTV() public {
        vm.prank(poolOwner);
        riskEngine.requestLtvUpdate(linearRatePool, address(asset2), 0.75e18);

        vm.startPrank(makeAddr("notOwner"));
        vm.expectRevert();
        riskEngine.acceptLtvUpdate(linearRatePool, address(asset2));

        vm.expectRevert();
        riskEngine.rejectLtvUpdate(linearRatePool, address(asset2));

        assertEq(riskEngine.ltvFor(linearRatePool, address(asset2)), 0);
    }

    function testCannotSetLTVOutsideGlobalLimits() public {
        vm.prank(riskEngine.owner());
        riskEngine.setLtvBounds(0.25e18, 0.75e18);

        vm.startPrank(poolOwner);
        vm.expectRevert();
        riskEngine.requestLtvUpdate(linearRatePool, address(asset1), 0.24e18);

        vm.expectRevert();
        riskEngine.requestLtvUpdate(linearRatePool, address(asset1), 0.76e18);

        assertEq(riskEngine.ltvFor(linearRatePool, address(asset1)), 0);
    }

    function testCanUpdateRiskModule() public {
        vm.prank(protocolOwner);
        riskEngine.setRiskModule(address(0x3828342));
        assertEq(address(riskEngine.riskModule()), address(0x3828342));

        vm.startPrank(address(0x21));
        vm.expectRevert();
        riskEngine.setRiskModule(address(0x821813));
    }

    function testCannotUpdateLTVBeforeTimelock() public {
        vm.startPrank(poolOwner);
        riskEngine.requestLtvUpdate(linearRatePool, address(asset2), 0.75e18);
        riskEngine.acceptLtvUpdate(linearRatePool, address(asset2));

        riskEngine.requestLtvUpdate(linearRatePool, address(asset2), 0.5e18);

        vm.expectRevert();
        riskEngine.acceptLtvUpdate(linearRatePool, address(asset2));

        assertEq(riskEngine.ltvFor(linearRatePool, address(asset2)), 0.75e18);

        vm.warp(block.timestamp + 2 days);

        riskEngine.acceptLtvUpdate(linearRatePool, address(asset2));
    }
}
