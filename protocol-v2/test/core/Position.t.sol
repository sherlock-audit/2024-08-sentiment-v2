// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseTest.t.sol";

import { FixedRateModel } from "../../src/irm/FixedRateModel.sol";
import { LinearRateModel } from "../../src/irm/LinearRateModel.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { Action, Operation } from "src/PositionManager.sol";
import { FixedPriceOracle } from "src/oracle/FixedPriceOracle.sol";

contract PositionUnitTests is BaseTest {
    Pool pool;
    address payable position;
    RiskEngine riskEngine;
    PositionManager positionManager;
    address positionOwner = makeAddr("positionOwner");
    FixedPriceOracle asset1Oracle;
    FixedPriceOracle asset2Oracle;
    FixedPriceOracle asset3Oracle;

    function setUp() public override {
        super.setUp();

        asset1Oracle = new FixedPriceOracle(10e18);
        asset2Oracle = new FixedPriceOracle(0.5e18);
        asset3Oracle = new FixedPriceOracle(1e18);

        pool = protocol.pool();
        riskEngine = protocol.riskEngine();
        positionManager = protocol.positionManager();

        vm.startPrank(protocolOwner);
        riskEngine.setOracle(address(asset1), address(asset1Oracle));
        riskEngine.setOracle(address(asset2), address(asset2Oracle));
        riskEngine.setOracle(address(asset3), address(asset3Oracle));
        vm.stopPrank();

        asset1.mint(address(this), 10_000 ether);
        asset1.approve(address(pool), 10_000 ether);

        pool.deposit(linearRatePool, 10_000 ether, address(0x9));

        Action[] memory actions = new Action[](1);
        (position, actions[0]) = newPosition(positionOwner, bytes32(uint256(3_492_932_942)));
        PositionManager(positionManager).processBatch(position, actions);

        vm.startPrank(poolOwner);
        riskEngine.requestLtvUpdate(linearRatePool, address(asset2), 0.75e18);
        riskEngine.acceptLtvUpdate(linearRatePool, address(asset2));

        riskEngine.requestLtvUpdate(linearRatePool, address(asset3), 0.75e18);
        riskEngine.acceptLtvUpdate(linearRatePool, address(asset3));
        vm.stopPrank();
    }

    function testInitNewPositionRaw() public {
        address pool2 = makeAddr("pool2");
        address positionManager2 = makeAddr("positionManager2");

        Position newPosition = new Position(pool2, positionManager2);

        assertEq(address(newPosition.POOL()), pool2);
        assertEq(address(newPosition.POSITION_MANAGER()), positionManager2);
    }

    function testCannotCallNonAuthorizedFunctions() public {
        address hacker = makeAddr("hacker");
        vm.startPrank(hacker);

        vm.expectRevert();
        Position(position).approve(address(asset2), hacker, 10_000 ether);

        // So the call doesn't revert for a lack of balance
        asset2.mint(address(position), 10_000 ether);

        vm.expectRevert();
        Position(position).transfer(address(asset2), hacker, 10_000 ether);

        vm.expectRevert();
        Position(position).borrow(linearRatePool, 10_000 ether);

        vm.expectRevert();
        Position(position).repay(linearRatePool, 10_000 ether);

        vm.expectRevert();
        Position(position).addToken(address(asset2));

        vm.expectRevert();
        Position(position).removeToken(address(asset2));

        vm.expectRevert();
        Position(position).exec(address(0x0), 0, bytes(""));
    }

    function testCannotExceedPoolMaxLength() public {
        vm.startPrank(address(positionManager));

        for (uint256 i = 1; i < 6; i++) {
            Position(position).addToken(address(vm.addr(i)));
        }

        vm.expectRevert();
        Position(position).addToken(address(vm.addr(6)));

        for (uint256 i = 1; i < 6; i++) {
            Position(position).borrow(i, 10_000 ether);
        }

        vm.expectRevert();
        Position(position).borrow(6, 10_000 ether);
    }
}
