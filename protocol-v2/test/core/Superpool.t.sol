// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseTest.t.sol";
import { console2 } from "forge-std/console2.sol";
import { FixedPriceOracle } from "src/oracle/FixedPriceOracle.sol";

contract SuperPoolUnitTests is BaseTest {
    uint256 initialDepositAmt = 1e5;

    Pool pool;
    Registry registry;
    SuperPool superPool;
    RiskEngine riskEngine;
    SuperPoolFactory superPoolFactory;

    address public feeTo = makeAddr("FeeTo");

    function setUp() public override {
        super.setUp();

        pool = protocol.pool();
        registry = protocol.registry();
        riskEngine = protocol.riskEngine();
        superPoolFactory = protocol.superPoolFactory();

        FixedPriceOracle asset1Oracle = new FixedPriceOracle(1e18);
        vm.prank(protocolOwner);
        riskEngine.setOracle(address(asset1), address(asset1Oracle));

        vm.prank(protocolOwner);
        asset1.mint(address(this), initialDepositAmt);
        asset1.approve(address(superPoolFactory), initialDepositAmt);

        superPool = SuperPool(
            superPoolFactory.deploySuperPool(
                poolOwner, address(asset1), feeTo, 0.01 ether, 1_000_000 ether, initialDepositAmt, "test", "test"
            )
        );
    }

    function testInitSuperPoolFactory() public {
        superPoolFactory = new SuperPoolFactory(address(pool));
        assertEq(superPoolFactory.POOL(), address(pool));
    }

    function testInitSuperPool() public {
        SuperPool randomPoolRaw =
            new SuperPool(address(pool), address(asset1), feeTo, 0.01 ether, 1_000_000 ether, "test", "test");

        assertEq(address(randomPoolRaw.asset()), address(asset1));
        assertEq(randomPoolRaw.feeRecipient(), feeTo);
        assertEq(randomPoolRaw.fee(), 0.01 ether);
        assertEq(randomPoolRaw.superPoolCap(), 1_000_000 ether);
        assertEq(randomPoolRaw.name(), "test");
        assertEq(randomPoolRaw.symbol(), "test");
    }

    function testDeployAPoolFromFactory() public {
        address feeRecipient = makeAddr("FeeRecipient");

        vm.prank(protocolOwner);
        asset1.mint(address(this), initialDepositAmt);
        asset1.approve(address(superPoolFactory), initialDepositAmt);

        address deployed = superPoolFactory.deploySuperPool(
            poolOwner, address(asset1), feeRecipient, 0, type(uint256).max, initialDepositAmt, "test", "test"
        );

        assert(deployed != address(0));
        SuperPool _superPool = SuperPool(deployed);
        assertEq(_superPool.owner(), poolOwner);
        assertEq(address(_superPool.asset()), address(asset1));
        assertEq(_superPool.feeRecipient(), feeRecipient);
        assertEq(_superPool.fee(), 0);
        assertEq(_superPool.superPoolCap(), type(uint256).max);
        assertEq(_superPool.name(), "test");
        assertEq(_superPool.symbol(), "test");
    }

    function testAddPoolToSuperPool() public {
        assertEq(superPool.getPoolCount(), 0);
        assertEq(superPool.pools().length, 0);

        vm.prank(poolOwner);
        superPool.addPool(linearRatePool, 100 ether);

        assertEq(superPool.getPoolCount(), 1);
        assertEq(superPool.pools().length, 1);
        assertEq(superPool.poolCapFor(linearRatePool), 100 ether);

        vm.prank(poolOwner);
        vm.expectRevert(); // Cannot mix asset types when initializing pool types
        superPool.addPool(alternateAssetPool, 100 ether);

        address linearRateModel = address(new LinearRateModel(2e18, 3e18));
        bytes32 RATE_MODEL_KEY = 0xc6e8fa81936202e651519e9ac3074fa4a42c65daad3fded162373ba224d6ea96;
        vm.prank(protocolOwner);
        Registry(registry).setRateModel(RATE_MODEL_KEY, linearRateModel);

        vm.startPrank(poolOwner);
        uint256 linearPool = pool.initializePool(poolOwner, address(asset1), type(uint128).max, RATE_MODEL_KEY);
        superPool.addPool(linearPool, 50 ether);
        vm.stopPrank();
    }

    function testRemovePoolFromSuperPool() public {
        vm.startPrank(poolOwner);
        superPool.addPool(linearRatePool, 100 ether);

        assertEq(superPool.getPoolCount(), 1);
        assertEq(superPool.pools().length, 1);
        assertEq(superPool.poolCapFor(linearRatePool), 100 ether);

        superPool.addPool(fixedRatePool, 100 ether);

        assertEq(superPool.getPoolCount(), 2);
        assertEq(superPool.pools().length, 2);
        assertEq(superPool.poolCapFor(fixedRatePool), 100 ether);

        superPool.addPool(linearRatePool2, 100 ether);
        superPool.addPool(fixedRatePool2, 100 ether);

        superPool.removePool(linearRatePool2, false);

        assertEq(superPool.getPoolCount(), 3);
        assertEq(superPool.pools().length, 3);
        assertEq(superPool.poolCapFor(linearRatePool2), 0);
    }

    function testCanModifyPoolCap() public {
        vm.startPrank(poolOwner);
        superPool.addPool(linearRatePool, 100 ether);
        assertEq(superPool.poolCapFor(linearRatePool), 100 ether);

        assertEq(superPool.getPoolCount(), 1);
        assertEq(superPool.pools().length, 1);

        superPool.modifyPoolCap(linearRatePool, 200 ether);
        assertEq(superPool.poolCapFor(linearRatePool), 200 ether);

        assertEq(superPool.getPoolCount(), 1);
        assertEq(superPool.pools().length, 1);
    }

    function testNonAdminCannotModifyPoolCaps() public {
        vm.startPrank(user);
        vm.expectRevert();
        superPool.addPool(linearRatePool, 100 ether);
    }

    function testSimpleDepositIntoSuperpool() public {
        vm.startPrank(poolOwner);
        superPool.addPool(linearRatePool, 100 ether);
        vm.stopPrank();

        vm.startPrank(user);

        asset1.mint(user, 100 ether);
        asset1.approve(address(superPool), 100 ether);

        uint256 expectedShares = superPool.previewDeposit(100 ether);
        uint256 shares = superPool.deposit(100 ether, user);
        assertEq(shares, expectedShares);

        assertEq(asset1.balanceOf(address(pool)), 100 ether);
        vm.stopPrank();
    }

    function testZeroShareDeposit() public {
        vm.startPrank(poolOwner);
        superPool.addPool(linearRatePool, 100 ether);
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(SuperPool.SuperPool_ZeroShareDeposit.selector, address(superPool), 0));
        superPool.deposit(0, user);
    }

    function testWithdrawalScenarios() public {
        testSimpleDepositIntoSuperpool();
        uint256 shares = superPool.balanceOf(user);
        uint256 assets = superPool.convertToAssets(shares);

        vm.prank(user);
        superPool.approve(user2, shares / 10);

        vm.startPrank(user2);
        superPool.redeem(shares / 10, user2, user);

        vm.expectRevert();
        superPool.withdraw(assets / 10, user2, user);
        vm.stopPrank();

        vm.prank(user);
        superPool.approve(user2, type(uint256).max);

        vm.prank(user2);
        superPool.withdraw(assets / 2, user2, user);

        // coincidenal withdrawal can be covered without dipping into base pools
        asset1.mint(address(superPool), assets / 10);

        vm.prank(user);
        superPool.withdraw(assets / 10, user, user);
    }

    function testWithdrawFromPausedPool() public {
        testSimpleDepositIntoSuperpool();

        vm.startPrank(pool.positionManager());
        pool.borrow(linearRatePool, makeAddr("position"), 100 ether);
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(SuperPool.SuperPool_NotEnoughLiquidity.selector, address(superPool)));
        superPool.withdraw(10 ether, user, user);
    }

    function testTotalAssets(uint96 amount) public {
        vm.assume(amount > 1e6);
        vm.assume(amount < superPool.superPoolCap() - initialDepositAmt);

        vm.startPrank(poolOwner);
        superPool.addPool(linearRatePool, amount);
        superPool.addPool(fixedRatePool, amount);
        vm.stopPrank();

        vm.startPrank(user);
        asset1.mint(user, amount);
        asset1.approve(address(superPool), amount);
        superPool.deposit(amount, user);
        vm.stopPrank();

        assertEq(superPool.totalAssets(), amount + initialDepositAmt);
    }

    function testSimpleDepositIntoMultiplePools() public {
        vm.startPrank(poolOwner);
        superPool.addPool(linearRatePool, 100 ether);
        superPool.addPool(fixedRatePool, 100 ether);
        vm.stopPrank();

        vm.startPrank(user);

        asset1.mint(user, 200 ether);
        asset1.approve(address(superPool), 200 ether);

        uint256 expectedShares = superPool.previewDeposit(200 ether);
        uint256 shares = superPool.deposit(200 ether, user);

        assertEq(shares, expectedShares);
        assertEq(asset1.balanceOf(address(pool)), 200 ether);
    }

    function testDepositMoreThanPoolCap() public {
        vm.startPrank(poolOwner);
        superPool.addPool(linearRatePool, 50 ether);
        vm.stopPrank();

        vm.startPrank(user);
        asset1.mint(user, 100 ether);
        asset1.approve(address(superPool), 100 ether);

        superPool.deposit(100 ether, user);
        assertEq(asset1.balanceOf(address(superPool)), 50 ether + initialDepositAmt);
    }

    function testPartialWithdrawal(uint96 amt) public {
        vm.assume(amt > 1e6);
        vm.assume(amt < superPool.superPoolCap() - initialDepositAmt);
        vm.startPrank(poolOwner);
        superPool.addPool(linearRatePool, amt / 2);
        superPool.addPool(fixedRatePool, (amt / 2) + 1);
        vm.stopPrank();

        vm.startPrank(user);

        asset1.mint(user, amt);
        asset1.approve(address(superPool), amt);

        uint256 totalShares = superPool.deposit(amt, user);

        uint256 expectedAssets = superPool.previewRedeem(totalShares / 2);
        uint256 assets = superPool.redeem(totalShares / 2, user, user);
        assertEq(assets, expectedAssets);
        assertEq(asset1.balanceOf(user), amt / 2);

        uint256 expectedShares = superPool.previewWithdraw(amt / 2);
        uint256 shares = superPool.withdraw(amt / 2, user, user);
        assertEq(shares, expectedShares);
        assertApproxEqAbs(asset1.balanceOf(user), amt, 1);
    }

    function testSetFeeRecipient() public {
        vm.startPrank(poolOwner);
        superPool.setFeeRecipient(feeTo);
        assertEq(superPool.feeRecipient(), feeTo);
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert();
        superPool.setFeeRecipient(user);
    }

    function testSetSuperPoolCap() public {
        vm.startPrank(poolOwner);
        superPool.setSuperpoolCap(1_000_000 ether);
        assertEq(superPool.superPoolCap(), 1_000_000 ether);
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert();
        superPool.setSuperpoolCap(1_000_000 ether);
    }

    function testSetSuperPoolFee() public {
        vm.startPrank(poolOwner);
        superPool.requestFeeUpdate(0.04 ether);
        vm.warp(26 hours);
        superPool.acceptFeeUpdate();
        assertEq(superPool.fee(), 0.04 ether);
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert();
        superPool.requestFeeUpdate(0.04 ether);
    }

    function testToggleAllocator() public {
        vm.startPrank(poolOwner);

        address newAllocator = makeAddr("NewAllocator");

        superPool.toggleAllocator(newAllocator);
        assertEq(superPool.isAllocator(newAllocator), true);
        superPool.toggleAllocator(newAllocator);
        assertEq(superPool.isAllocator(newAllocator), false);
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert();
        superPool.toggleAllocator(makeAddr("BadAllocator"));
    }

    function invariantMaxDepositsStayConsistent() public view {
        uint256 maxDepositAssets = superPool.maxDeposit(user);
        uint256 maxDepositShares = superPool.maxMint(user);

        assertApproxEqAbs(maxDepositShares, superPool.convertToShares(maxDepositAssets), 1);
    }

    function testMaxDepositIncreasesWithHigherCap() public {
        vm.startPrank(poolOwner);
        superPool.setSuperpoolCap(100 ether);
        vm.stopPrank();

        vm.startPrank(user);
        uint256 maxDepositAssets = superPool.maxDeposit(user);
        uint256 maxDepositShares = superPool.maxMint(user);
        vm.stopPrank();

        assertApproxEqAbs(maxDepositShares, superPool.convertToShares(maxDepositAssets), 1);

        vm.startPrank(poolOwner);
        superPool.setSuperpoolCap(200 ether);
        vm.stopPrank();

        vm.startPrank(user);
        uint256 newMaxDepositAssets = superPool.maxDeposit(user);
        uint256 newMaxDepositShares = superPool.maxMint(user);
        vm.stopPrank();

        assertApproxEqAbs(newMaxDepositShares, superPool.convertToShares(newMaxDepositAssets), 1);
        assertGt(newMaxDepositAssets, maxDepositAssets);
        assertGt(newMaxDepositShares, maxDepositShares);
    }

    function testSupplyMoreThanCurrentPoolCaps() public {
        vm.startPrank(poolOwner);
        superPool.addPool(fixedRatePool, 100 ether);
        superPool.addPool(linearRatePool, 100 ether);
        vm.stopPrank();

        vm.startPrank(user);
        asset1.mint(user, 201 ether);
        asset1.approve(address(superPool), 201 ether);
        superPool.deposit(200 ether, user);

        superPool.deposit(1 ether, user);
        assertEq(asset1.balanceOf(address(superPool)), 1 ether + initialDepositAmt);
    }

    function invariantMaxWithdrawalsStayConsistent() public view {
        uint256 maxWithdrawAssets = superPool.maxWithdraw(user);
        uint256 maxWithdrawShares = superPool.maxRedeem(user);

        assertApproxEqAbs(maxWithdrawAssets, superPool.convertToAssets(maxWithdrawShares), 1);
    }

    function testMaxWithdrawDecreasesAsYouWithdraw() public {
        testSimpleDepositIntoSuperpool();

        uint256 maxWithdrawAssets = superPool.maxWithdraw(user);
        uint256 maxWithdrawShares = superPool.maxRedeem(user);

        assertEq(maxWithdrawAssets, 100 ether);
        assertApproxEqAbs(maxWithdrawAssets, superPool.convertToAssets(maxWithdrawShares), 1);

        vm.startPrank(user);
        superPool.withdraw(50 ether, user, user);
        vm.stopPrank();

        uint256 newMaxWithdrawAssets = superPool.maxWithdraw(user);
        uint256 newMaxWithdrawShares = superPool.maxRedeem(user);

        assertEq(newMaxWithdrawAssets, 50 ether);
        assertLt(newMaxWithdrawAssets, maxWithdrawAssets);
        assertLt(newMaxWithdrawShares, maxWithdrawShares);
    }

    function testAMoreComplexScenario() public {
        // 1. Initialize FixedRatePool and LinearRatePool each with a 50 ether cap
        // 2. User1, and User2 each deposit 50 ether into the superpool
        // 3. Lower the cap on FixedRatePool by 10 ether, raise it on LinearRatePool by the same
        // 4. ReAllocate
        // 5. Both users withdraw fully

        vm.startPrank(poolOwner);
        superPool.addPool(fixedRatePool, 50 ether);
        superPool.addPool(linearRatePool, 50 ether);
        vm.stopPrank();

        vm.startPrank(user);
        asset1.mint(user, 50 ether);
        asset1.approve(address(superPool), 50 ether);
        superPool.deposit(50 ether, user);
        vm.stopPrank();

        vm.startPrank(user2);
        asset1.mint(user2, 50 ether);
        asset1.approve(address(superPool), 50 ether);
        superPool.deposit(50 ether, user2);
        vm.stopPrank();

        vm.startPrank(poolOwner);
        superPool.modifyPoolCap(fixedRatePool, 40 ether);
        superPool.modifyPoolCap(linearRatePool, 60 ether);
        vm.stopPrank();

        SuperPool.ReallocateParams[] memory reAllocateDeposits = new SuperPool.ReallocateParams[](1);
        SuperPool.ReallocateParams[] memory reAllocateWithdrawals = new SuperPool.ReallocateParams[](1);

        superPool.accrue();

        reAllocateDeposits[0] = (SuperPool.ReallocateParams(fixedRatePool, 10 ether));
        reAllocateWithdrawals[0] = (SuperPool.ReallocateParams(linearRatePool, 10 ether));

        vm.startPrank(user);
        vm.expectRevert();
        superPool.reallocate(reAllocateWithdrawals, reAllocateDeposits); // Regular user cannot reallocate
        vm.stopPrank();

        vm.prank(poolOwner);
        superPool.reallocate(reAllocateWithdrawals, reAllocateDeposits);

        vm.startPrank(user);
        superPool.withdraw(50 ether, user, user);
        vm.stopPrank();

        vm.startPrank(user2);
        superPool.withdraw(50 ether, user2, user2);
        vm.stopPrank();
    }

    function testReallocateDeposits() public {
        vm.startPrank(poolOwner);
        superPool.addPool(fixedRatePool, 50 ether);
        superPool.addPool(linearRatePool, 50 ether);
        superPool.addPool(fixedRatePool2, 50 ether);
        superPool.addPool(linearRatePool2, 50 ether);
        vm.stopPrank();

        uint256[] memory newWrongDepositOrder = new uint256[](3);
        newWrongDepositOrder[0] = 0;
        newWrongDepositOrder[1] = 1;
        newWrongDepositOrder[2] = 2;
        // newDepositOrder[3] = linearRatePool2;

        vm.expectRevert();
        superPool.reorderDepositQueue(newWrongDepositOrder);

        vm.startPrank(poolOwner);

        vm.expectRevert();
        superPool.reorderDepositQueue(newWrongDepositOrder);

        uint256[] memory newDepositOrder = new uint256[](4);
        newDepositOrder[0] = 3;
        newDepositOrder[1] = 2;
        newDepositOrder[2] = 1;
        newDepositOrder[3] = 0;

        superPool.reorderDepositQueue(newDepositOrder);
        vm.stopPrank();

        assertEq(superPool.depositQueue(3), fixedRatePool);
        assertEq(superPool.depositQueue(2), linearRatePool);
        assertEq(superPool.depositQueue(1), fixedRatePool2);
        assertEq(superPool.depositQueue(0), linearRatePool2);
    }

    function testReorderWithdrawals() public {
        vm.startPrank(poolOwner);
        superPool.addPool(fixedRatePool, 50 ether);
        superPool.addPool(linearRatePool, 50 ether);
        superPool.addPool(fixedRatePool2, 50 ether);
        superPool.addPool(linearRatePool2, 50 ether);
        vm.stopPrank();

        uint256[] memory newWrongWithdrawalOrder = new uint256[](100);
        newWrongWithdrawalOrder[0] = 2;

        vm.expectRevert();
        superPool.reorderWithdrawQueue(newWrongWithdrawalOrder);

        vm.startPrank(poolOwner);
        vm.expectRevert(abi.encodeWithSelector(SuperPool.SuperPool_QueueLengthMismatch.selector, address(superPool)));
        superPool.reorderWithdrawQueue(newWrongWithdrawalOrder);

        uint256[] memory newWithdrawalOrder = new uint256[](4);
        newWithdrawalOrder[0] = 3;
        newWithdrawalOrder[1] = 2;
        newWithdrawalOrder[2] = 1;
        newWithdrawalOrder[3] = 0;

        superPool.reorderWithdrawQueue(newWithdrawalOrder);

        assertEq(superPool.withdrawQueue(3), fixedRatePool);
        assertEq(superPool.withdrawQueue(2), linearRatePool);
        assertEq(superPool.withdrawQueue(1), fixedRatePool2);
        assertEq(superPool.withdrawQueue(0), linearRatePool2);
    }

    function testInterestEarnedOnTheUnderlingPool() public {
        // 1. Setup a basic pool with an asset1
        // 2. Add it to the superpool
        // 3. Deposit assets into the pool
        // 4. Borrow from an alternate account
        // 5. accrueInterest
        // 6. Attempt to withdraw all of the liquidity, and see the running out of the pool
        vm.startPrank(poolOwner);
        superPool.addPool(linearRatePool, 50 ether);
        superPool.addPool(fixedRatePool, 50 ether);
        vm.stopPrank();

        vm.startPrank(user);
        asset1.mint(user, 50 ether);
        asset1.approve(address(superPool), 50 ether);

        vm.expectRevert();
        superPool.deposit(0, user);

        superPool.deposit(50 ether, user);
        vm.stopPrank();

        vm.startPrank(Pool(pool).positionManager());
        Pool(pool).borrow(linearRatePool, user, 35 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + 365 days);
        vm.roll(block.number + 5_000_000);
        pool.accrue(linearRatePool);

        vm.startPrank(Pool(pool).positionManager());
        uint256 borrowsOwed = pool.getBorrowsOf(linearRatePool, user);

        asset1.mint(Pool(pool).positionManager(), borrowsOwed);
        asset1.approve(address(pool), borrowsOwed);
        Pool(pool).repay(linearRatePool, user, borrowsOwed);
        vm.stopPrank();

        superPool.accrue();

        vm.startPrank(user);
        vm.expectRevert(); // Not enough liquidity
        superPool.withdraw(40 ether, user, user);
        vm.stopPrank();

        vm.startPrank(poolOwner);
        vm.expectRevert(); // Cant remove a pool with liquidity in it
        superPool.removePool(linearRatePool, false);
        vm.stopPrank();
    }
}
