// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../BaseTest.t.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { FixedPriceOracle } from "src/oracle/FixedPriceOracle.sol";

contract PoolUnitTests is BaseTest {
    // keccak(SENTIMENT_POSITION_MANAGER_KEY)
    bytes32 public constant SENTIMENT_POSITION_MANAGER_KEY =
        0xd4927490fbcbcafca716cca8e8c8b7d19cda785679d224b14f15ce2a9a93e148;

    Pool pool;
    Registry registry;
    RiskEngine riskEngine;

    function setUp() public override {
        super.setUp();
        pool = protocol.pool();
        registry = protocol.registry();
        riskEngine = protocol.riskEngine();

        FixedPriceOracle asset1Oracle = new FixedPriceOracle(1e18);
        vm.prank(protocolOwner);
        riskEngine.setOracle(address(asset1), address(asset1Oracle));
    }

    function testIntializePool() public {
        // test constructor
        address poolImpl = address(new Pool());
        Pool testPool = Pool(address(new TransparentUpgradeableProxy(poolImpl, protocolOwner, new bytes(0))));
        testPool.initialize(protocolOwner, 0, 0, address(registry), address(0), 0, 0);
        assertEq(testPool.registry(), address(registry));

        address rateModel = address(new LinearRateModel(1e18, 2e18));
        bytes32 RATE_MODEL_KEY = 0xc6e8fa81936202e651519e9ac3074fa4a42c65daad3fded162373ba224d6ea96;
        vm.prank(protocolOwner);
        registry.setRateModel(RATE_MODEL_KEY, rateModel);
        uint256 id = testPool.initializePool(poolOwner, address(asset1), type(uint128).max, RATE_MODEL_KEY);
        assertEq(rateModel, testPool.getRateModelFor(id));
    }

    /// @dev Foundry "fails" keyword
    function testFailsDoubleInit() public {
        address rateModel = address(new LinearRateModel(1e18, 2e18));
        bytes32 RATE_MODEL_KEY = 0xc6e8fa81936202e651519e9ac3074fa4a42c65daad3fded162373ba224d6ea96;
        vm.prank(protocolOwner);
        registry.setRateModel(RATE_MODEL_KEY, rateModel);

        pool.initializePool(poolOwner, address(asset1), type(uint128).max, RATE_MODEL_KEY);
        pool.initializePool(poolOwner, address(asset1), type(uint128).max, RATE_MODEL_KEY);
    }

    function testCannotFrontRunDeployment() public {
        address notPoolOwner = makeAddr("notPoolOwner");
        address rateModel = address(new LinearRateModel(1e18, 2e18));
        bytes32 RATE_MODEL_KEY = 0xc6e8fa81936202e651519e9ac3074fa4a42c65daad3fded162373ba224d6ea96;
        vm.prank(protocolOwner);
        registry.setRateModel(RATE_MODEL_KEY, rateModel);

        vm.prank(poolOwner);
        uint256 id = pool.initializePool(poolOwner, address(asset1), type(uint128).max, RATE_MODEL_KEY);

        vm.prank(notPoolOwner);
        uint256 id2 = pool.initializePool(notPoolOwner, address(asset1), type(uint128).max, RATE_MODEL_KEY);

        assert(id != id2);
    }

    function testCannotDepositNothing() public {
        vm.startPrank(user);
        asset1.approve(address(pool), 0);

        vm.expectRevert(abi.encodeWithSelector(Pool.Pool_ZeroSharesDeposit.selector, linearRatePool, 0));
        pool.deposit(linearRatePool, 0, user);
    }

    function testCanDepositAssets(uint96 assets) public {
        vm.assume(assets > 0);
        vm.startPrank(user);

        asset1.mint(user, assets);
        asset1.approve(address(pool), assets);

        pool.deposit(linearRatePool, assets, user);

        assertEq(pool.getAssetsOf(linearRatePool, user), assets);
        assertEq(pool.balanceOf(user, linearRatePool), assets); // Shares equal 1:1 at first

        vm.stopPrank();
    }

    function testDepositPausedPool(uint96 assets) public {
        vm.assume(assets > 0);
        vm.prank(poolOwner);
        pool.togglePause(linearRatePool);
        vm.startPrank(user);
        asset1.mint(user, assets);
        asset1.approve(address(pool), assets);
        vm.expectRevert(abi.encodeWithSelector(Pool.Pool_PoolPaused.selector, linearRatePool));
        pool.deposit(linearRatePool, assets, user);
        vm.stopPrank();
    }

    function testCanWithdrawAssets(uint96 assets) public {
        testCanDepositAssets(assets);

        vm.prank(user);
        pool.withdraw(linearRatePool, assets, user, user);

        assertEq(pool.getAssetsOf(linearRatePool, user), 0);
        assertEq(pool.balanceOf(user, linearRatePool), 0);

        assertEq(asset1.balanceOf(user), assets);
    }

    function testCannotWithdrawOthersAssets(uint96 assets) public {
        testCanDepositAssets(assets);

        address notLender = makeAddr("notLender");

        vm.startPrank(user);
        vm.expectRevert();
        pool.withdraw(linearRatePool, assets, user, notLender);
    }

    function testCannotWithdrawNoShares() public {
        vm.startPrank(user);

        vm.expectRevert(abi.encodeWithSelector(Pool.Pool_ZeroShareRedeem.selector, linearRatePool, 0));
        pool.withdraw(linearRatePool, 0, user, user);
    }

    function testCanWithdrawOthersAssetsWithApproval(uint96 assets) public {
        testCanDepositAssets(assets);

        address approvedUser = makeAddr("approvedUser");

        vm.prank(user);
        pool.approve(approvedUser, linearRatePool, assets);

        vm.prank(approvedUser);
        pool.withdraw(linearRatePool, assets, approvedUser, user);

        assertEq(pool.getAssetsOf(linearRatePool, user), 0);
        assertEq(pool.balanceOf(user, linearRatePool), 0);

        assertEq(asset1.balanceOf(approvedUser), assets);
    }

    function testOperatorCanManageOthersAssets(uint96 assets) public {
        testCanDepositAssets(assets);

        address operator = makeAddr("operator");

        vm.prank(user);
        pool.setOperator(operator, true);

        vm.prank(operator);
        pool.withdraw(linearRatePool, assets, operator, user);

        assertEq(pool.getAssetsOf(linearRatePool, user), 0);
        assertEq(pool.balanceOf(user, linearRatePool), 0);

        assertEq(asset1.balanceOf(operator), assets);
    }

    function testOnlyPositionManagerCanBorrow() public {
        address notPositionManager = makeAddr("notPositionManager");
        vm.startPrank(notPositionManager);
        vm.expectRevert(
            abi.encodeWithSelector(Pool.Pool_OnlyPositionManager.selector, linearRatePool, notPositionManager)
        );
        pool.borrow(linearRatePool, notPositionManager, 100 ether);
    }

    function testCannotBorrowZeroShares(uint96 assets) public {
        testCanDepositAssets(assets);

        vm.startPrank(registry.addressFor(SENTIMENT_POSITION_MANAGER_KEY));

        vm.expectRevert(abi.encodeWithSelector(Pool.Pool_ZeroSharesBorrow.selector, linearRatePool, uint256(0)));
        pool.borrow(linearRatePool, user, 0);
    }

    function testBorrowWorksAsIntended(uint96 _assets) public {
        vm.assume(_assets > 1000);
        testCanDepositAssets(_assets);

        uint256 assets = uint256(_assets);

        vm.prank(registry.addressFor(SENTIMENT_POSITION_MANAGER_KEY));
        pool.borrow(linearRatePool, user, assets / 5);

        assertEq(pool.getAssetsOf(linearRatePool, user), assets);
        assertApproxEqAbs(asset1.balanceOf(address(pool)), assets * 4 / 5, 1);
        assertApproxEqAbs(asset1.balanceOf(user), assets / 5, 1);

        assertEq(pool.getBorrowsOf(linearRatePool, user), assets / 5);
        assertEq(pool.getTotalBorrows(linearRatePool), assets / 5);
    }

    function testBorrowPausedPool(uint96 _assets) public {
        vm.assume(_assets > 1000);

        testCanDepositAssets(_assets);

        vm.prank(poolOwner);
        pool.togglePause(linearRatePool);

        uint256 assets = uint256(_assets);
        vm.prank(registry.addressFor(SENTIMENT_POSITION_MANAGER_KEY));
        vm.expectRevert(abi.encodeWithSelector(Pool.Pool_PoolPaused.selector, linearRatePool));
        pool.borrow(linearRatePool, user, assets / 5);
    }

    function testTimeIncreasesDebt(uint96 assets) public {
        testBorrowWorksAsIntended(assets);

        (,,,,,,, uint256 totalBorrowAssets, uint256 totalBorrowShares,,) = pool.poolDataFor(linearRatePool);

        uint256 time = block.timestamp + 1 days;
        vm.warp(time + 86_400 * 7);
        vm.roll(block.number + ((86_400 * 7) / 2));

        pool.accrue(linearRatePool);

        (,,,,,,, uint256 newTotalBorrowAssets, uint256 newTotalBorrowShares,,) = pool.poolDataFor(linearRatePool);

        assertEq(newTotalBorrowShares, totalBorrowShares);
        assertGt(newTotalBorrowAssets, totalBorrowAssets);
    }

    function testCanWithdrawEarnedInterest(uint96 assets) public {
        testTimeIncreasesDebt(assets);

        (,,,,,,, uint256 totalBorrowAssets, uint256 totalBorrowShares,,) = pool.poolDataFor(linearRatePool);

        assertGt(totalBorrowAssets, totalBorrowShares);

        // Add some liquidity to the pool
        address user2 = makeAddr("user2");
        vm.startPrank(user2);
        asset1.mint(user2, assets);
        asset1.approve(address(pool), assets);
        pool.deposit(linearRatePool, assets, user2);

        vm.startPrank(user);
        pool.withdraw(linearRatePool, pool.balanceOf(user, linearRatePool), user, user);

        assertGt(asset1.balanceOf(user), assets);
    }

    function testRepayWorksAsIntended(uint96 assets) public {
        testBorrowWorksAsIntended(assets);

        uint256 borrowed = pool.getBorrowsOf(linearRatePool, user);

        vm.prank(registry.addressFor(SENTIMENT_POSITION_MANAGER_KEY));
        pool.repay(linearRatePool, user, borrowed / 2);

        assertApproxEqAbs(pool.getBorrowsOf(linearRatePool, user), borrowed / 2, 1);
        assertApproxEqAbs(pool.getTotalBorrows(linearRatePool), borrowed / 2, 1);
    }

    function testConvertToSharesAndAssetsAreReversible(uint112 frac1, uint96 number) public view {
        vm.assume(frac1 > 1e8);
        vm.assume(number > 0);

        uint256 totalAssets = uint256(frac1) * 2;
        uint256 totalShares = frac1;

        uint256 sharesFromAssets = pool.convertToShares(number, totalAssets, totalShares);
        uint256 assetsFromShares = pool.convertToAssets(sharesFromAssets, totalAssets, totalShares);

        assertApproxEqAbs(assetsFromShares, number, 2);
    }

    function testCantRepayForSomeoneElse() public {
        testBorrowWorksAsIntended(100 ether);

        uint256 borrowed = pool.getBorrowsOf(linearRatePool, user);

        vm.startPrank(makeAddr("notPositionManager"));

        vm.expectRevert();
        pool.repay(linearRatePool, user, borrowed / 2);
    }

    function testCannotRepayZero() public {
        testBorrowWorksAsIntended(100 ether);

        vm.startPrank(registry.addressFor(SENTIMENT_POSITION_MANAGER_KEY));
        vm.expectRevert();
        pool.repay(linearRatePool, user, 0);
    }

    function testOwnerCanPause() public {
        (bool isPaused,,,,,,,,,,) = pool.poolDataFor(linearRatePool);
        assertFalse(isPaused);

        vm.prank(poolOwner);
        pool.togglePause(linearRatePool);

        (isPaused,,,,,,,,,,) = pool.poolDataFor(linearRatePool);
        assertTrue(isPaused);
    }

    function testOnlyPoolOwnerCanPause(address sender) public {
        vm.assume(sender != poolOwner);
        vm.assume(sender != proxyAdmin);
        vm.expectRevert(abi.encodeWithSelector(Pool.Pool_OnlyPoolOwner.selector, linearRatePool, sender));
        vm.prank(sender);
        pool.togglePause(linearRatePool);
    }

    function testOwnerCanSetCap(uint128 newPoolCap) public {
        (,,, uint256 poolCap,,,,,,,) = pool.poolDataFor(linearRatePool);
        assert(poolCap == type(uint128).max);

        vm.prank(poolOwner);
        pool.setPoolCap(linearRatePool, newPoolCap);

        (,,, poolCap,,,,,,,) = pool.poolDataFor(linearRatePool);
        assertEq(poolCap, newPoolCap);
    }

    function testOnlyPoolOwnerCanSetCap(address sender, uint128 poolCap) public {
        vm.assume(sender != poolOwner);
        vm.assume(sender != proxyAdmin);
        vm.expectRevert(abi.encodeWithSelector(Pool.Pool_OnlyPoolOwner.selector, linearRatePool, sender));
        vm.prank(sender);
        pool.setPoolCap(linearRatePool, poolCap);
    }

    function testOwnerCanRequestRateModelUpdate(address newRateModel) public {
        vm.assume(newRateModel != address(0));

        vm.prank(protocolOwner);
        registry.setRateModel("NEW_RATE_MODEL", newRateModel);

        vm.prank(poolOwner);
        pool.requestRateModelUpdate(linearRatePool, "NEW_RATE_MODEL");

        (address rateModel,) = pool.rateModelUpdateFor(linearRatePool);
        assertEq(rateModel, newRateModel);
    }

    function testOnlyOwnerCanRequestRateModelUpdate(address sender, address newRateModel) public {
        vm.assume(sender != poolOwner);
        vm.assume(sender != proxyAdmin);

        vm.prank(protocolOwner);
        registry.setRateModel("NEW_RATE_MODEL", newRateModel);

        vm.expectRevert(abi.encodeWithSelector(Pool.Pool_OnlyPoolOwner.selector, linearRatePool, sender));
        vm.prank(sender);
        pool.requestRateModelUpdate(linearRatePool, "NEW_RATE_MODEL");
    }

    function testRateModelUpdateTimelockWorks(address newRateModel) public {
        testOwnerCanRequestRateModelUpdate(newRateModel);

        (, uint256 validAfter) = pool.rateModelUpdateFor(linearRatePool);

        vm.prank(poolOwner);
        vm.expectRevert(
            abi.encodeWithSelector(Pool.Pool_TimelockPending.selector, linearRatePool, block.timestamp, validAfter)
        );
        pool.acceptRateModelUpdate(linearRatePool);
    }

    function testOwnerCanAcceptRateModelUpdate(address newRateModel) public {
        testOwnerCanRequestRateModelUpdate(newRateModel);
        (, uint256 validAfter) = pool.rateModelUpdateFor(linearRatePool);
        assertEq(validAfter, block.timestamp + pool.TIMELOCK_DURATION());

        vm.warp(validAfter);
        vm.prank(poolOwner);
        pool.acceptRateModelUpdate(linearRatePool);

        (,, address rateModel,,,,,,,,) = pool.poolDataFor(linearRatePool);
        assertEq(rateModel, newRateModel);
    }

    function testOnlyOwnerCanAcceptRateModelUpdate(address sender) public {
        vm.assume(sender != poolOwner);
        vm.assume(sender != proxyAdmin);
        vm.expectRevert(abi.encodeWithSelector(Pool.Pool_OnlyPoolOwner.selector, linearRatePool, sender));
        vm.prank(sender);
        pool.acceptRateModelUpdate(linearRatePool);
    }

    function testOwnerCanRejectModelUpdate(address newRateModel) public {
        testOwnerCanRequestRateModelUpdate(newRateModel);

        vm.prank(poolOwner);
        pool.rejectRateModelUpdate(linearRatePool);

        (address rateModel, uint256 validAfter) = pool.rateModelUpdateFor(linearRatePool);
        assertEq(rateModel, address(0));
        assertEq(validAfter, 0);
    }

    function testNoRateModelUpdate() public {
        vm.prank(poolOwner);
        vm.expectRevert(abi.encodeWithSelector(Pool.Pool_NoRateModelUpdate.selector, linearRatePool));
        pool.acceptRateModelUpdate(linearRatePool);
    }

    function testOnlyOwnerCanRejectModelUpdate(address sender) public {
        vm.assume(sender != poolOwner);
        vm.assume(sender != proxyAdmin);
        vm.expectRevert(abi.encodeWithSelector(Pool.Pool_OnlyPoolOwner.selector, linearRatePool, sender));
        vm.prank(sender);
        pool.rejectRateModelUpdate(linearRatePool);
    }

    function testPoolLiquidityIsNotShared() public {
        vm.startPrank(user);

        asset1.mint(user, 200 ether);
        asset1.approve(address(pool), 200 ether);

        pool.deposit(linearRatePool, 100 ether, user);
        pool.deposit(fixedRatePool, 100 ether, user);
        vm.stopPrank();

        vm.prank(registry.addressFor(SENTIMENT_POSITION_MANAGER_KEY));
        pool.borrow(linearRatePool, user, 50 ether);

        vm.startPrank(user);

        vm.expectRevert();
        pool.withdraw(linearRatePool, 100 ether, user, user);
    }

    function testOwnerCanSetRegistry() public {
        Registry newRegistry = new Registry();
        vm.prank(protocolOwner);
        pool.setRegistry(address(newRegistry));
        assertEq(pool.registry(), address(newRegistry));
    }

    function testOnlyOwnerCanSetRegistry(address sender, address newRegistry) public {
        vm.assume(sender != protocolOwner);
        vm.prank(sender);
        vm.expectRevert();
        pool.setRegistry(newRegistry);
    }

    function testPoolCap(uint96 assets, uint96 newPoolCap) public {
        vm.assume(assets > 0);
        vm.assume(newPoolCap < assets);

        vm.prank(poolOwner);
        pool.setPoolCap(linearRatePool, newPoolCap);

        vm.startPrank(user);
        asset1.mint(user, assets);
        asset1.approve(address(pool), assets);
        vm.expectRevert(abi.encodeWithSelector(Pool.Pool_PoolCapExceeded.selector, linearRatePool));
        pool.deposit(linearRatePool, assets, user);
        vm.stopPrank();
    }
}
