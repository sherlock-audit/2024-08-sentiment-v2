// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../BaseTest.t.sol";
import { Action, Operation } from "src/PositionManager.sol";
import { IOracle } from "src/interfaces/IOracle.sol";
import { FixedPriceOracle } from "src/oracle/FixedPriceOracle.sol";

contract FailedRepayAll is BaseTest {
    // keccak(SENTIMENT_POOL_KEY)
    bytes32 public constant SENTIMENT_POOL_KEY = 0x1a99cbf6006db18a0e08427ff11db78f3ea1054bc5b9d48122aae8d206c09728;
    // keccak(SENTIMENT_RISK_ENGINE_KEY)
    bytes32 public constant SENTIMENT_RISK_ENGINE_KEY =
        0x5b6696788621a5d6b5e3b02a69896b9dd824ebf1631584f038a393c29b6d7555;
    // keccak(SENIMENT_POSITION_BEACON_KEY)
    bytes32 public constant SENTIMENT_POSITION_BEACON_KEY =
        0xc77ea3242ed8f193508dbbe062eaeef25819b43b511cbe2fc5bd5de7e23b9990;

    Pool pool;
    Registry registry;
    address position;
    RiskEngine riskEngine;
    PositionManager positionManager;

    address public positionOwner = makeAddr("positionOwner");
    FixedPriceOracle asset1Oracle = new FixedPriceOracle(10e18);
    FixedPriceOracle asset2Oracle = new FixedPriceOracle(0.5e18);
    FixedPriceOracle asset3Oracle = new FixedPriceOracle(10e18);

    function setUp() public override {
        super.setUp();

        asset1Oracle = new FixedPriceOracle(10e18);
        asset2Oracle = new FixedPriceOracle(0.5e18);
        asset3Oracle = new FixedPriceOracle(10e18);

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

    function testCanDepositAssets(uint96 assets) public {
        vm.assume(assets > 0);
        vm.startPrank(user);

        asset1.mint(user, assets);
        asset1.approve(address(pool), assets);

        pool.deposit(linearRatePool, assets, user);

        assertEq(pool.getAssetsOf(linearRatePool, user), assets);
        assertEq(pool.balanceOf(user, linearRatePool), assets);

        vm.stopPrank();
    }

    function testBorrowWorksAsIntended(uint96 _assets) public {
        vm.assume(_assets > 1000);
        testCanDepositAssets(_assets);

        uint256 assets = uint256(_assets);

        vm.prank(address(positionManager));
        pool.borrow(linearRatePool, user, assets / 5);

        assertEq(pool.getAssetsOf(linearRatePool, user), assets);
        assertApproxEqAbs(asset1.balanceOf(user), assets / 5, 1);

        assertEq(pool.getBorrowsOf(linearRatePool, user), assets / 5);
        assertEq(pool.getTotalBorrows(linearRatePool), assets / 5);
    }

    function testTimeIncreasesDebt(uint96 assets) public {
        testBorrowWorksAsIntended(assets);

        (,,,,,,, uint256 totalBorrowAssets, uint256 totalBorrowShares,,) = pool.poolDataFor(linearRatePool);

        uint256 time = block.timestamp + 1 days;
        vm.warp(time + 86_400 * 365);
        vm.roll(block.number + ((86_400 * 365) / 2));

        pool.accrue(linearRatePool);

        (,,,,,,, uint256 newTotalBorrowAssets, uint256 newTotalBorrowShares,,) = pool.poolDataFor(linearRatePool);

        assertEq(newTotalBorrowShares, totalBorrowShares);
        assertGt(newTotalBorrowAssets, totalBorrowAssets);
    }

    function test_poc_RepayFail() public {
        // Underlying pool has some actions that changes share:asset ratio
        testTimeIncreasesDebt(10e18);
        (,,,,,,, uint256 totalBorrowAssets, uint256 totalBorrowShares,,) = pool.poolDataFor(linearRatePool);
        assertGt(totalBorrowAssets, totalBorrowShares);

        // Mint some tokens to position owner
        asset1.mint(positionOwner, 2 ether); // User will transfer it to Position contract when repay
        asset2.mint(positionOwner, 1000 ether); // This will be collateral when borrow

        // A user deposits some collateral via PositionManager (It's asset2 which is worth 0.5)
        vm.startPrank(positionOwner);
        Action[] memory actions = new Action[](1);
        actions[0] = addToken(address(asset2));
        PositionManager(positionManager).processBatch(position, actions);
        actions[0] = deposit(address(asset2), 1000 ether);
        asset2.approve(address(positionManager), 1000 ether);
        PositionManager(positionManager).processBatch(position, actions);

        // User borrows via PositionManager (asset1)
        bytes memory data = abi.encode(linearRatePool, 10 ether);
        Action memory actionBorrow = Action({ op: Operation.Borrow, data: data });
        Action[] memory actionsBorrow = new Action[](1);
        actionsBorrow[0] = actionBorrow;
        PositionManager(positionManager).processBatch(position, actionsBorrow);

        // Some time passes (a month)
        uint256 time = block.timestamp;
        vm.warp(time + 86_400 * 30);
        vm.roll(block.number + ((86_400 * 30) / 2));
        pool.accrue(linearRatePool);

        //-----------REPAY--------------
        // User first transfers some asset to Position contract to be able to pay interest.
        asset1.transfer(position, 2 ether);

        // User tries to repay all.
        uint256 x = type(uint256).max;
        bytes memory dataRepay = abi.encode(linearRatePool, x);
        Action memory actionRepay = Action({ op: Operation.Repay, data: dataRepay });
        Action[] memory actionsRepay = new Action[](1);
        actionsRepay[0] = actionRepay;

        // This action will fail with "debt too low" error even though the user has enough balance and passed the
        // uint256.max as an input
        // There will be 1 borrow share left because of the rounding.
        // vm.expectRevert(abi.encodeWithSelector(RiskModule.RiskModule_DebtTooLow.selector, position, 20)); // 20 is
        // remaining debt based on console result and foundry traces.
        positionManager.processBatch(position, actionsRepay);
    }
}
