// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { FixedRateModel } from "../../src/irm/FixedRateModel.sol";
import { LinearRateModel } from "../../src/irm/LinearRateModel.sol";
import "../BaseTest.t.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Action, Operation } from "src/PositionManager.sol";
import { IOracle } from "src/interfaces/IOracle.sol";
import { FixedPriceOracle } from "src/oracle/FixedPriceOracle.sol";

contract PositionManagerUnitTests is BaseTest {
    // keccak(SENTIMENT_POOL_KEY)
    bytes32 public constant SENTIMENT_POOL_KEY = 0x1a99cbf6006db18a0e08427ff11db78f3ea1054bc5b9d48122aae8d206c09728;
    // keccak(SENTIMENT_RISK_ENGINE_KEY)
    bytes32 public constant SENTIMENT_RISK_ENGINE_KEY =
        0x5b6696788621a5d6b5e3b02a69896b9dd824ebf1631584f038a393c29b6d7555;
    // keccak(SENIMENT_POSITION_BEACON_KEY)
    bytes32 public constant SENTIMENT_POSITION_BEACON_KEY =
        0x6e7384c78b0e09fb848f35d00a7b14fc1ad10ae9b10117368146c0e09b6f2fa2;

    Pool pool;
    Registry registry;
    address payable position;
    RiskEngine riskEngine;
    PositionManager positionManager;

    address public positionOwner = makeAddr("positionOwner");
    FixedPriceOracle asset1Oracle;
    FixedPriceOracle asset2Oracle;
    FixedPriceOracle asset3Oracle;

    function setUp() public override {
        super.setUp();

        asset1Oracle = new FixedPriceOracle(10e18);
        asset2Oracle = new FixedPriceOracle(0.5e18);
        asset3Oracle = new FixedPriceOracle(1e18);

        pool = protocol.pool();
        registry = protocol.registry();
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
        riskEngine.requestLtvUpdate(linearRatePool, address(asset3), 0.75e18);
        riskEngine.acceptLtvUpdate(linearRatePool, address(asset3));
        riskEngine.requestLtvUpdate(linearRatePool, address(asset2), 0.75e18);
        riskEngine.acceptLtvUpdate(linearRatePool, address(asset2));
        vm.stopPrank();
    }

    function testInitPositionManagerFromConstructor() public {
        // registry
        registry = new Registry();

        // position manager
        address positionManagerImpl = address(new PositionManager()); // deploy impl
        address beacon = address((new TransparentUpgradeableProxy(positionManagerImpl, positionOwner, new bytes(0))));
        positionManager = PositionManager(beacon); // setup proxy

        PositionManager(positionManager).initialize(protocolOwner, address(registry), 550);

        registry.setAddress(SENTIMENT_POSITION_BEACON_KEY, beacon);
        registry.setAddress(SENTIMENT_POOL_KEY, address(pool));
        registry.setAddress(SENTIMENT_RISK_ENGINE_KEY, address(riskEngine));

        PositionManager(positionManager).updateFromRegistry();

        assertEq(address(positionManager.pool()), address(pool));
        assertEq(address(positionManager.riskEngine()), address(riskEngine));
        assertEq(positionManager.positionBeacon(), beacon);
    }

    function testInitializePosition() public {
        address expectedAddress;
        Action[] memory actions = new Action[](1);
        (expectedAddress, actions[0]) = newPosition(positionOwner, bytes32(uint256(43_534_853)));

        PositionManager(positionManager).processBatch(expectedAddress, actions);

        uint32 size;
        assembly {
            size := extcodesize(expectedAddress)
        }

        assertGt(size, 0);
    }

    function testInitializeIncorrectPosition() public {
        bytes32 salt = bytes32(uint256(43_534_853));
        bytes memory data = abi.encode(positionOwner, salt);
        Action memory action = Action({ op: Operation.NewPosition, data: data });

        Action[] memory actions = new Action[](1);
        actions[0] = action;

        vm.expectRevert();
        PositionManager(positionManager).processBatch(makeAddr("incorrectPosition"), actions);

        vm.expectRevert();
        PositionManager(positionManager).process(makeAddr("incorrectPosition"), action);
    }

    function testAddAndRemoveCollateralTypes() public {
        vm.startPrank(positionOwner);

        Action[] memory actions = new Action[](1);
        actions[0] = addToken(address(asset2));

        PositionManager(positionManager).processBatch(position, actions);

        assertEq(Position(position).getPositionAssets().length, 1);
        assertEq(Position(position).getPositionAssets()[0], address(asset2));

        Action[] memory actions2 = new Action[](1);
        actions2[0] = removeToken(address(asset2));

        PositionManager(positionManager).processBatch(position, actions2);
        assertEq(Position(position).getPositionAssets().length, 0);
    }

    function testSimpleDepositCollateral(uint96 amount) public {
        vm.assume(amount > 0);
        asset2.mint(positionOwner, amount);

        vm.startPrank(positionOwner);
        Action[] memory actions = new Action[](1);

        actions[0] = addToken(address(asset2));
        PositionManager(positionManager).processBatch(position, actions);

        actions[0] = deposit(address(asset2), amount);
        asset2.approve(address(positionManager), amount);
        PositionManager(positionManager).processBatch(position, actions);

        (uint256 totalAssetValue, uint256 totalDebtValue, uint256 minReqAssetValue) = riskEngine.getRiskData(position);
        assertEq(
            totalAssetValue, IOracle(riskEngine.getOracleFor(address(asset2))).getValueInEth(address(asset2), amount)
        );
        assertEq(totalDebtValue, 0);
        assertEq(minReqAssetValue, 0);
        assertEq(asset2.balanceOf(address(position)), amount);

        vm.stopPrank();
    }

    function testSimpleTransfer() public {
        testSimpleDepositCollateral(100 ether);

        vm.prank(positionManager.owner());
        positionManager.toggleKnownAsset(address(asset2));

        vm.startPrank(positionOwner);
        // bytes memory data = abi.encode(address(positionOwner), address(asset2), 50 ether);
        // Action memory action = Action({ op: Operation.Transfer, data: data });
        Action[] memory actions = new Action[](1);
        actions[0] = transfer(positionOwner, address(asset2), 50 ether);

        vm.expectRevert();
        PositionManager(positionManager).processBatch(position, actions);

        vm.expectRevert();
        PositionManager(positionManager).process(position, actions[0]);
        vm.stopPrank();

        vm.prank(positionManager.owner());
        positionManager.toggleKnownAsset(address(asset2));

        vm.startPrank(positionOwner);
        uint256 initialCollateral = asset2.balanceOf(positionOwner);
        PositionManager(positionManager).processBatch(position, actions);
        assertEq(asset2.balanceOf(positionOwner), initialCollateral + 50 ether);

        initialCollateral = asset2.balanceOf(positionOwner);
        PositionManager(positionManager).process(position, actions[0]);
        assertEq(asset2.balanceOf(positionOwner), initialCollateral + 50 ether);
        vm.stopPrank();
    }

    function testSimpleBorrow() public {
        testSimpleDepositCollateral(100 ether);

        vm.startPrank(positionOwner);
        bytes memory data = abi.encode(linearRatePool, 2 ether);

        Action memory action = Action({ op: Operation.Borrow, data: data });
        Action[] memory actions = new Action[](1);
        actions[0] = action;

        uint256 initialAssetBalance = asset1.balanceOf(position);
        (,,,,,,, uint256 totalBorrowAssets,,,) = pool.poolDataFor(linearRatePool);
        assertEq(address(positionManager.pool()), address(pool));

        PositionManager(positionManager).processBatch(position, actions);

        assertGt(asset1.balanceOf(position), initialAssetBalance);
        (,,,,,,, uint256 newTotalBorrowAssets,,,) = pool.poolDataFor(linearRatePool);
        assertEq(newTotalBorrowAssets, totalBorrowAssets + 2 ether);
    }

    // TODO: rewrite test with a third asset to allow zero ltv
    // function testZeroLtvBorrow() public {
    //     testSimpleDepositCollateral(100 ether);

    //     vm.startPrank(poolOwner);
    //     riskEngine.requestLtvUpdate(linearRatePool, address(asset2), 0);
    //     vm.warp(block.timestamp + 1 days);
    //     riskEngine.acceptLtvUpdate(linearRatePool, address(asset2));
    //     vm.stopPrank();

    //     vm.startPrank(positionOwner);
    //     bytes memory data = abi.encode(linearRatePool, 2 ether);

    //     Action memory action = Action({ op: Operation.Borrow, data: data });

    //     vm.expectRevert(
    //         abi.encodeWithSelector(
    //             RiskModule.RiskModule_UnsupportedAsset.selector, position, linearRatePool, address(asset2)
    //         )
    //     );
    //     PositionManager(positionManager).process(position, action);
    // }

    function testMinDebtCheck() public {
        testSimpleDepositCollateral(100 ether);

        vm.prank(protocolOwner);
        pool.setMinDebt(0.05 ether);

        Action memory action = borrow(linearRatePool, 0.001e18); // 1 asset1 = 10 eth => 1/1000 asset1 = 0.01 eth
        vm.prank(positionOwner);
        vm.expectRevert(abi.encodeWithSelector(Pool.Pool_DebtTooLow.selector, linearRatePool, asset1, 0.001 ether));
        positionManager.process(position, action);
    }

    function testCannotBorrowFromDeadPool() public {
        testSimpleDepositCollateral(100 ether);

        address rateModel = address(new LinearRateModel(1e18, 2e18));
        bytes32 RATE_MODEL_KEY = 0xc6e8fa81936202e651519e9ac3074fa4a42c65daad3fded162373ba224d6ea96;
        vm.prank(protocolOwner);
        registry.setRateModel(RATE_MODEL_KEY, rateModel);

        uint256 corruptPool = pool.initializePool(address(0xdead), address(asset1), type(uint128).max, RATE_MODEL_KEY);

        vm.startPrank(positionOwner);
        bytes memory data = abi.encode(corruptPool, 2 ether);

        Action memory action = Action({ op: Operation.Borrow, data: data });
        Action[] memory actions = new Action[](1);
        actions[0] = action;

        vm.expectRevert();
        PositionManager(positionManager).processBatch(position, actions);
    }

    function testSimpleRepay() public {
        testSimpleBorrow();

        vm.startPrank(positionOwner);
        bytes memory data = abi.encode(linearRatePool, 1 ether);

        Action memory action = Action({ op: Operation.Repay, data: data });
        Action[] memory actions = new Action[](1);
        actions[0] = action;

        (,,,,,,, uint256 totalBorrowAssets,,,) = pool.poolDataFor(linearRatePool);
        uint256 initialBorrow = pool.getBorrowsOf(linearRatePool, position);

        PositionManager(positionManager).processBatch(position, actions);

        (,,,,,,, uint256 newTotalBorrowAssets,,,) = pool.poolDataFor(linearRatePool);

        uint256 borrow = pool.getBorrowsOf(linearRatePool, position);

        assertLt(borrow, initialBorrow);
        assertLt(newTotalBorrowAssets, totalBorrowAssets);
    }

    function testFullRepay() public {
        testSimpleBorrow();

        uint256 borrow = pool.getBorrowsOf(linearRatePool, position);

        vm.startPrank(positionOwner);
        bytes memory data = abi.encode(linearRatePool, borrow);

        asset1.mint(position, 5 ether);

        Action memory action = Action({ op: Operation.Repay, data: data });
        Action[] memory actions = new Action[](1);
        actions[0] = action;

        assertEq(Position(position).getDebtPools().length, 1);

        PositionManager(positionManager).processBatch(position, actions);

        assertEq(Position(position).getDebtPools().length, 0);
    }

    function testSimpleExec() public {
        TestCallContract testContract = new TestCallContract(false);

        bytes memory data = abi.encodePacked(address(testContract), uint256(0), bytes4(keccak256("testCall()")));
        Action memory action = Action({ op: Operation.Exec, data: data });
        Action[] memory actions = new Action[](1);
        actions[0] = action;

        // vm.prank(positionManager.owner());
        // positionManager.toggleKnownAsset(address(testContract));
        vm.prank(positionManager.owner());
        positionManager.toggleKnownFunc(address(testContract), bytes4(keccak256("testCall()")));

        assertEq(testContract.ping(), 0);

        vm.startPrank(positionOwner);

        PositionManager(positionManager).processBatch(position, actions);

        assertEq(testContract.ping(), 1);
    }

    function testSimpleFailedCall() public {
        TestCallContract testContract = new TestCallContract(true);

        bytes memory data = abi.encodePacked(address(testContract), bytes4(keccak256("testCall()")));
        Action memory action = Action({ op: Operation.Exec, data: data });
        Action[] memory actions = new Action[](1);
        actions[0] = action;

        // vm.prank(positionManager.owner());
        // positionManager.toggleKnownAddress(address(testContract));
        vm.prank(positionManager.owner());
        positionManager.toggleKnownFunc(address(testContract), bytes4(keccak256("testCall()")));

        assertEq(testContract.ping(), 0);

        vm.startPrank(positionOwner);

        vm.expectRevert();
        PositionManager(positionManager).process(position, action);

        assertEq(testContract.ping(), 0);
    }

    function testExecNegativeCases() public {
        TestCallContract testContract = new TestCallContract(false);

        bytes memory data = abi.encodePacked(address(testContract), uint256(0), bytes4(keccak256("testCall()")));
        Action memory action = Action({ op: Operation.Exec, data: data });

        vm.startPrank(positionOwner);
        vm.expectRevert();
        PositionManager(positionManager).process(position, action);
        vm.stopPrank();

        // vm.prank(positionManager.owner());
        // positionManager.toggleKnownAddress(address(testContract));

        assertEq(testContract.ping(), 0);

        vm.startPrank(positionOwner);
        vm.expectRevert();
        PositionManager(positionManager).process(position, action);
        vm.stopPrank();

        vm.prank(positionManager.owner());
        positionManager.toggleKnownFunc(address(testContract), bytes4(keccak256("testCall()")));

        assertEq(testContract.ping(), 0);

        vm.startPrank(positionOwner);
        PositionManager(positionManager).process(position, action);
        vm.stopPrank();

        assertEq(testContract.ping(), 1);
    }

    // Test setting the beacon address
    function testSetBeacon() public {
        address newBeacon = makeAddr("newBeacon");
        vm.prank(positionManager.owner());
        positionManager.setBeacon(newBeacon);
        assertEq(positionManager.positionBeacon(), newBeacon, "Beacon address should be updated");

        vm.startPrank(makeAddr("nonOwner")); // Non-owner address
        vm.expectRevert();
        positionManager.setBeacon(newBeacon);
    }

    // Test setting the liquidation fee
    function testSetLiquidationFee() public {
        uint256 newFee = 100; // Example fee
        vm.prank(positionManager.owner());
        positionManager.setLiquidationFee(newFee);
        assertEq(positionManager.liquidationFee(), newFee, "Liquidation fee should be updated");

        vm.startPrank(makeAddr("nonOwner")); // Non-owner address
        vm.expectRevert();
        positionManager.setLiquidationFee(newFee);
    }

    // Test toggling known asset
    function testToggleKnownAsset() public {
        address target = makeAddr("target");
        bool initialState = positionManager.isKnownAsset(target);

        vm.prank(positionManager.owner());
        positionManager.toggleKnownAsset(target);
        assertEq(positionManager.isKnownAsset(target), !initialState, "Known address state should be toggled");

        vm.startPrank(makeAddr("nonOwner")); // Non-owner address
        vm.expectRevert();
        positionManager.toggleKnownAsset(target);
    }

    // Test toggling known function
    function testToggleKnownFunc() public {
        address target = makeAddr("target");
        bytes4 method = bytes4(keccak256("testMethod()"));
        bool initialState = positionManager.isKnownFunc(target, method);

        vm.prank(positionManager.owner());
        positionManager.toggleKnownFunc(target, method);
        assertEq(positionManager.isKnownFunc(target, method), !initialState, "Known function state should be toggled");

        vm.startPrank(makeAddr("nonOwner")); // Non-owner address
        vm.expectRevert();
        positionManager.toggleKnownFunc(target, method);
    }

    function testApproveAction() public {
        testSimpleDepositCollateral(100 ether);

        address spender = makeAddr("spender");

        vm.startPrank(positionOwner);
        Action memory action = approve(spender, address(asset2), 100 ether);

        vm.expectRevert();
        PositionManager(positionManager).process(position, action);
        vm.stopPrank();

        vm.startPrank(positionOwner);
        vm.expectRevert();
        PositionManager(positionManager).process(position, action);
        vm.stopPrank();

        vm.prank(positionManager.owner());
        positionManager.toggleKnownSpender(spender);

        vm.prank(positionOwner);
        PositionManager(positionManager).process(position, action);

        vm.prank(spender);
        asset2.transferFrom(address(position), address(spender), 100 ether);
    }

    function testToggleAuth() public {
        vm.startPrank(positionOwner);
        Action memory action = addToken(address(asset2));

        PositionManager(positionManager).process(position, action);

        address newOwner = makeAddr("newOwner");
        vm.stopPrank();

        vm.startPrank(newOwner);
        action = addToken(address(asset1));

        vm.expectRevert();
        PositionManager(positionManager).process(position, action);
        vm.stopPrank();

        vm.startPrank(makeAddr("aRandomGuy"));
        vm.expectRevert();
        positionManager.toggleAuth(newOwner, position);
        vm.stopPrank();

        vm.prank(positionOwner);
        positionManager.toggleAuth(newOwner, position);

        vm.prank(newOwner);
        PositionManager(positionManager).process(position, action);
    }

    function testNoInsolventActions() public {
        testSimpleDepositCollateral(1 ether);

        vm.startPrank(positionOwner);
        bytes memory data = abi.encode(linearRatePool, 1000 ether);
        Action memory action = Action({ op: Operation.Borrow, data: data });
        Action[] memory actions = new Action[](1);
        actions[0] = action;

        vm.expectRevert();
        PositionManager(positionManager).processBatch(position, actions);

        vm.expectRevert();
        PositionManager(positionManager).process(position, action);
    }

    function testCanSetRegistry() public {
        Registry newRegistry = new Registry();
        vm.prank(protocolOwner);
        positionManager.setRegistry(address(newRegistry));
        assertEq(address(positionManager.registry()), address(newRegistry));
    }

    function testOnlyOwnerCanSetRegistry(address sender, address newRegistry) public {
        vm.assume(sender != protocolOwner);
        vm.prank(sender);
        vm.expectRevert();
        positionManager.setRegistry(newRegistry);
    }
}

contract TestCallContract {
    bool immutable revertOrNot;
    uint256 public ping;

    constructor(bool _revertOrNot) {
        revertOrNot = _revertOrNot;
    }

    function testCall() public {
        if (revertOrNot) revert("Call Revert");
        ping++;
    }
}
