// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { BaseTest } from "../BaseTest.t.sol";
import { Pool } from "src/Pool.sol";
import { PositionManager } from "src/PositionManager.sol";
import { Action, AssetData, DebtData } from "src/PositionManager.sol";
import { RiskEngine } from "src/RiskEngine.sol";
import { RiskModule } from "src/RiskModule.sol";
import { FixedPriceOracle } from "src/oracle/FixedPriceOracle.sol";

contract LiquidationTest is BaseTest {
    Pool pool;
    address position;
    RiskEngine riskEngine;
    PositionManager positionManager;
    address public liquidator = makeAddr("liquidator");

    function setUp() public override {
        super.setUp();

        pool = protocol.pool();
        riskEngine = protocol.riskEngine();
        positionManager = protocol.positionManager();

        // ZeroOracle zeroOracle = new ZeroOracle();
        FixedPriceOracle oneEthOracle = new FixedPriceOracle(1e18);

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

    function testLiquidate() public {
        vm.startPrank(user);
        asset2.approve(address(positionManager), 1e18);

        // deposit 1e18 asset2, borrow 1e18 asset1
        Action[] memory actions = new Action[](7);
        (position, actions[0]) = newPosition(user, bytes32(uint256(0x123456789)));
        actions[1] = deposit(address(asset2), 1e18);
        actions[2] = addToken(address(asset2));
        actions[3] = borrow(fixedRatePool, 1e18);
        actions[4] = approve(address(mockswap), address(asset1), 1e18);
        bytes memory data = abi.encodeWithSelector(SWAP_FUNC_SELECTOR, address(asset1), address(asset3), 1e18);
        actions[5] = exec(address(mockswap), 0, data);
        actions[6] = addToken(address(asset3));
        positionManager.processBatch(position, actions);
        vm.stopPrank();
        assertTrue(riskEngine.isPositionHealthy(position));

        (uint256 totalAssetValue, uint256 totalDebtValue, uint256 minReqAssetValue) = riskEngine.getRiskData(position);

        assertEq(totalAssetValue, 2e18);
        assertEq(totalDebtValue, 1e18);
        assertEq(minReqAssetValue, 2e18);

        // construct liquidator data
        DebtData memory debtData = DebtData({ poolId: fixedRatePool, amt: type(uint256).max });
        DebtData[] memory debts = new DebtData[](1);
        debts[0] = debtData;
        AssetData memory asset1Data = AssetData({ asset: address(asset3), amt: 1e18 });
        AssetData memory asset2Data = AssetData({ asset: address(asset2), amt: 1e18 });
        AssetData[] memory assets = new AssetData[](2);
        assets[0] = asset1Data;
        assets[1] = asset2Data;

        // attempt to liquidate before price moves
        asset1.mint(liquidator, 10e18);
        vm.startPrank(liquidator);
        asset1.approve(address(positionManager), 1e18);
        vm.expectRevert(abi.encodeWithSelector(RiskModule.RiskModule_LiquidateHealthyPosition.selector, position));
        positionManager.liquidate(position, debts, assets);
        vm.stopPrank();

        // modify asset2 price from 1eth to 0.1eth
        FixedPriceOracle pointOneEthOracle = new FixedPriceOracle(0.1e18);
        vm.prank(protocolOwner);
        riskEngine.setOracle(address(asset2), address(pointOneEthOracle));
        assertFalse(riskEngine.isPositionHealthy(position));

        // liquidate
        vm.startPrank(liquidator);
        asset1.approve(address(positionManager), 1e18);
        positionManager.liquidate(position, debts, assets);
        vm.stopPrank();
    }

    function testSeizeTooMuch() public {
        vm.startPrank(user);
        asset2.approve(address(positionManager), 1e18);

        // deposit 1e18 asset2, borrow 1e18 asset1
        Action[] memory actions = new Action[](7);
        (position, actions[0]) = newPosition(user, bytes32(uint256(0x123456789)));
        actions[1] = deposit(address(asset2), 1e18);
        actions[2] = addToken(address(asset2));
        actions[3] = borrow(fixedRatePool, 1e18);
        actions[4] = approve(address(mockswap), address(asset1), 1e18);
        bytes memory data = abi.encodeWithSelector(SWAP_FUNC_SELECTOR, address(asset1), address(asset3), 1e18);
        actions[5] = exec(address(mockswap), 0, data);
        actions[6] = addToken(address(asset3));
        positionManager.processBatch(position, actions);
        vm.stopPrank();
        assertTrue(riskEngine.isPositionHealthy(position));

        (uint256 totalAssetValue, uint256 totalDebtValue, uint256 minReqAssetValue) = riskEngine.getRiskData(position);

        assertEq(totalAssetValue, 2e18);
        assertEq(totalDebtValue, 1e18);
        assertEq(minReqAssetValue, 2e18);

        // modify asset2 price from 1eth to 0.1eth
        FixedPriceOracle pointOneEthOracle = new FixedPriceOracle(0.1e18);
        vm.prank(protocolOwner);
        riskEngine.setOracle(address(asset2), address(pointOneEthOracle));
        assertFalse(riskEngine.isPositionHealthy(position));

        // construct liquidator data
        DebtData memory debtData = DebtData({ poolId: fixedRatePool, amt: 0.1e18 });
        DebtData[] memory debts = new DebtData[](1);
        debts[0] = debtData;
        AssetData memory asset1Data = AssetData({ asset: address(asset3), amt: 1e18 });
        AssetData memory asset2Data = AssetData({ asset: address(asset2), amt: 1e18 });
        AssetData[] memory assets = new AssetData[](2);
        assets[0] = asset1Data;
        assets[1] = asset2Data;

        // liquidate
        asset1.mint(liquidator, 10e18);
        vm.startPrank(liquidator);
        asset1.approve(address(positionManager), 1e18);
        vm.expectRevert(abi.encodeWithSelector(RiskModule.RiskModule_SeizedTooMuch.selector, 1.1 ether, 0.125 ether));
        positionManager.liquidate(position, debts, assets);
        vm.stopPrank();
    }
}
