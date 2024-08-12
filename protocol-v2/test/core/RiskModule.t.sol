// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { BaseTest, MockSwap } from "../BaseTest.t.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { Pool } from "src/Pool.sol";
import { Action } from "src/PositionManager.sol";
import { PositionManager } from "src/PositionManager.sol";
import { RiskEngine } from "src/RiskEngine.sol";
import { RiskModule } from "src/RiskModule.sol";
import { FixedPriceOracle } from "src/oracle/FixedPriceOracle.sol";

contract RiskModuleUnitTests is BaseTest {
    Pool pool;
    address position;
    RiskEngine riskEngine;
    RiskModule riskModule;
    PositionManager positionManager;

    FixedPriceOracle oneEthOracle;

    function setUp() public override {
        super.setUp();

        oneEthOracle = new FixedPriceOracle(1e18);

        pool = protocol.pool();
        riskEngine = protocol.riskEngine();
        riskModule = protocol.riskModule();
        positionManager = protocol.positionManager();

        vm.startPrank(protocolOwner);
        riskEngine.setOracle(address(asset1), address(oneEthOracle)); // 1 asset1 = 1 eth
        riskEngine.setOracle(address(asset2), address(oneEthOracle)); // 1 asset2 = 1 eth
        riskEngine.setOracle(address(asset3), address(oneEthOracle)); // 1 asset3 = 1 eth
        vm.stopPrank();

        vm.startPrank(poolOwner);
        riskEngine.requestLtvUpdate(fixedRatePool, address(asset3), 0.5e18); // 2x lev
        riskEngine.acceptLtvUpdate(fixedRatePool, address(asset3));
        riskEngine.requestLtvUpdate(fixedRatePool, address(asset2), 0.5e18); // 2x lev
        riskEngine.acceptLtvUpdate(fixedRatePool, address(asset2));
        vm.stopPrank();

        asset1.mint(lender, 100e18);
        asset2.mint(user, 10e18);

        vm.startPrank(lender);
        asset1.approve(address(pool), 100e18);
        pool.deposit(fixedRatePool, 100e18, lender);
        vm.stopPrank();
    }

    function testRiskModuleInit(address testRegistry, uint256 liqDiscount) public {
        RiskModule testRiskModule = new RiskModule(testRegistry, liqDiscount);

        assertEq(address(testRiskModule.REGISTRY()), testRegistry);
        assertEq(testRiskModule.LIQUIDATION_DISCOUNT(), liqDiscount);
    }

    function testAssetValueFuncs() public {
        vm.startPrank(user);
        asset2.approve(address(positionManager), 1e18);

        // deposit 1e18 asset2, borrow 1e18 asset1
        Action[] memory actions = new Action[](3);
        (position, actions[0]) = newPosition(user, bytes32(uint256(0x123456789)));
        actions[1] = deposit(address(asset2), 1e18);
        actions[2] = addToken(address(asset2));
        positionManager.processBatch(position, actions);
        vm.stopPrank();

        assertEq(riskModule.getTotalAssetValue(position), 1e18);
        assertEq(riskModule.getAssetValue(position, address(asset2)), 1e18);
    }

    function testDebtValueFuncs() public {
        vm.startPrank(user);
        asset2.approve(address(positionManager), 1e18);

        // deposit 1e18 asset2, borrow 1e18 asset1
        Action[] memory actions = new Action[](7);
        (position, actions[0]) = newPosition(user, bytes32(uint256(0x123456789)));
        actions[1] = deposit(address(asset2), 1e18);
        actions[2] = addToken(address(asset2));
        actions[3] = borrow(fixedRatePool, 1e18);
        actions[4] = approve(address(mockswap), address(asset1), 1e18);
        bytes memory data = abi.encodeWithSelector(MockSwap.swap.selector, address(asset1), address(asset3), 1e18);
        actions[5] = exec(address(mockswap), 0, data);
        actions[6] = addToken(address(asset3));
        positionManager.processBatch(position, actions);
        vm.stopPrank();

        assertEq(riskModule.getTotalDebtValue(position), 1e18);
        assertEq(riskModule.getDebtValueForPool(position, fixedRatePool), 1e18);
    }

    function testUnsupportedAsset() public {
        MockERC20 asset4 = new MockERC20("Asset4", "ASSET4", 18);
        asset4.mint(user, 10e18);

        vm.startPrank(protocolOwner);
        positionManager.toggleKnownAsset(address(asset4));
        riskEngine.setOracle(address(asset4), address(oneEthOracle));
        vm.stopPrank();

        vm.startPrank(user);
        asset4.approve(address(positionManager), 1e18);

        // deposit 1e18 asset4, borrow 1e18 asset1
        Action[] memory actions = new Action[](5);
        (position, actions[0]) = newPosition(user, bytes32(uint256(0x123456789)));
        actions[1] = deposit(address(asset4), 1e18);
        actions[2] = addToken(address(asset4));
        actions[3] = borrow(fixedRatePool, 1e18);
        actions[4] = addToken(address(asset1));

        vm.expectRevert(
            abi.encodeWithSelector(RiskModule.RiskModule_UnsupportedAsset.selector, position, fixedRatePool, asset4)
        );
        positionManager.processBatch(position, actions);
        vm.stopPrank();
    }
}
