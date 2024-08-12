// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { BaseTest } from "../BaseTest.t.sol";
import { Pool } from "src/Pool.sol";
import { PositionManager } from "src/PositionManager.sol";
import { Action, PositionManager } from "src/PositionManager.sol";
import { RiskEngine } from "src/RiskEngine.sol";
import { PortfolioLens } from "src/lens/PortfolioLens.sol";
import { FixedPriceOracle } from "src/oracle/FixedPriceOracle.sol";

contract PortfolioLensTest is BaseTest {
    Pool pool;
    address position;
    RiskEngine riskEngine;
    PortfolioLens portfolioLens;
    PositionManager positionManager;
    address[] public positions;

    function setUp() public override {
        super.setUp();

        pool = protocol.pool();
        riskEngine = protocol.riskEngine();
        portfolioLens = protocol.portfolioLens();
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
        vm.stopPrank();

        positions.push(position);
    }

    function testInitPortfolioLens() public {
        PortfolioLens testPfLens = new PortfolioLens(address(pool), address(riskEngine), address(positionManager));
        assertEq(address(testPfLens.POOL()), address(pool));
        assertEq(address(testPfLens.RISK_ENGINE()), address(riskEngine));
        assertEq(address(testPfLens.POSITION_MANAGER()), address(positionManager));
    }

    function testPortfolioData() public view {
        PortfolioLens.PortfolioData memory portfolioData = portfolioLens.getPortfolioData(positions);
        assertEq(portfolioData.positions[0].owner, user);
        assertEq(portfolioData.positions[0].position, position);
        _assertAssetData(portfolioData.positions[0].assets);
        _assertDebtData(portfolioData.positions[0].debts);
    }

    function testAssetData() public view {
        PortfolioLens.AssetData[] memory assetData = portfolioLens.getAssetData(position);
        _assertAssetData(assetData);
    }

    function testDebtData() public view {
        PortfolioLens.DebtData[] memory debtData = portfolioLens.getDebtData(position);
        _assertDebtData(debtData);
    }

    function testPositionData() public view {
        PortfolioLens.PositionData memory positionData = portfolioLens.getPositionData(position);
        assertEq(positionData.position, position);
        assertEq(positionData.owner, user);
        _assertAssetData(positionData.assets);
        _assertDebtData(positionData.debts);
    }

    function _assertAssetData(PortfolioLens.AssetData[] memory assetData) internal view {
        assertEq(assetData.length, 2);

        assertEq(assetData[0].asset, address(asset2));
        assertEq(assetData[0].amount, uint256(1e18));
        assertEq(assetData[0].valueInEth, uint256(1e18));

        assertEq(assetData[1].asset, address(asset3));
        assertEq(assetData[1].amount, uint256(1e18));
        assertEq(assetData[1].valueInEth, uint256(1e18));
    }

    function _assertDebtData(PortfolioLens.DebtData[] memory debtData) internal view {
        assertEq(debtData.length, 1);
        assertEq(debtData[0].poolId, fixedRatePool);
        assertEq(debtData[0].asset, address(asset1));
        assertEq(debtData[0].amount, uint256(1e18));
        assertEq(debtData[0].valueInEth, uint256(1e18));
        assertEq(debtData[0].interestRate, uint256(1e18));
    }
}
