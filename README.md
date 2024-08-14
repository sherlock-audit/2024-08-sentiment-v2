
# Sentiment V2 contest details

- Join [Sherlock Discord](https://discord.gg/MABEWyASkp)
- Submit findings using the issue page in your private contest repo (label issues as med or high)
- [Read for more details](https://docs.sherlock.xyz/audits/watsons)

# Q&A

### Q: On what chains are the smart contracts going to be deployed?
Any EVM-compatbile network
___

### Q: If you are integrating tokens, are you allowing only whitelisted tokens to work with the codebase or any complying with the standard? Are they assumed to have certain properties, e.g. be non-reentrant? Are there any types of [weird tokens](https://github.com/d-xo/weird-erc20) you want to integrate?
Tokens are whitelisted, only tokens with valid oracles can be used to create Base Pools.

Protocol governance will ensure that oracles are only set for standard ERC-20 tokens (plus USDC/USDT)
___

### Q: Are there any limitations on values set by admins (or other roles) in the codebase, including restrictions on array lengths?
Expected launch values for protocol params:
Min LTV = 10% = 100000000000000000
Max LTV = 98% = 980000000000000000
Min Debt = 0.05 ETH = 50000000000000000
Min Borrow = 0.05 ETH = 50000000000000000
Liquidation Fee = 0 (Might be increased to 20-30% in the future)
Liquidation Discount = 10% = 100000000000000000
Default Interest Fee = 10% = 100000000000000000
Default Origination Fee = 0
Sequencer Grace Period = 1 hour = 3600
Timelock Duration  = 24 hours (common across all contracts)
Timelock Deadline = 72 hours (common across all contracts)
MAX_QUEUE_LENGTH = 10
Max Position Assets = 5
Max Position Debt Pools = 5
___

### Q: Are there any limitations on values set by admins (or other roles) in protocols you integrate with, including restrictions on array lengths?
No.
___

### Q: For permissioned functions, please list all checks and requirements that will be made before calling the function.
All onlyOwner protocol functions will be controlled via a multisig, initially by the team and eventually by governance

All multisig operations will be simulated via Tenderly (or equivalent) before implementation
___

### Q: Is the codebase expected to comply with any EIPs? Can there be/are there any deviations from the specification?
SuperPool.sol is strictly ERC4626 compliant
Pool.sol is strictly ERC6909 compliant
___

### Q: Are there any off-chain mechanisms or off-chain procedures for the protocol (keeper bots, arbitrage bots, etc.)?
Liquidator bots: maintain protocol solvency through timely liquidation of risky positions
Reallocation bots: used to rebalance SuperPool deposits among respective base pools
___

### Q: Are there any hardcoded values that you intend to change before (some) deployments?
The following immutable might be modified before certain deployments:
Timelock Duration
Timelock Deadline
MAX_QUEUE_LENGTH
Max Position Assets
Max Position Debt Pools
___

### Q: If the codebase is to be deployed on an L2, what should be the behavior of the protocol in case of sequencer issues (if applicable)? Should Sherlock assume that the Sequencer won't misbehave, including going offline?
Issues due to sequencer going offline are valid only if they lead to a loss of funds and are not connected to price change risks.

Auditors can assume the sequencer is not overtly malicious.
___

### Q: Should potential issues, like broken assumptions about function behavior, be reported if they could pose risks in future integrations, even if they might not be an issue in the context of the scope? If yes, can you elaborate on properties/invariants that should hold?
No
___

### Q: Please discuss any design choices you made.
The deposit and withdraw flows in the SuperPool sequentially deposit and withdraw from pools. This can be inefficient at times. We assume that the SuperPool owner will use the reallocate function to rebalance liquidity among pools.

The purpose of bad debt liquidation is to ensure that the pool can revert back to a functional state after socialization of bad debt. It is expected that a small share of lenders might be able to withdraw funds before the function is executed.
___

### Q: Please list any known issues and explicitly state the acceptable risks for each known issue.
Previously acknowledged issues from past audits must be considered acceptable risks.

This condition can be overridden if a previously acknowledged issue can cause an issue of higher severity than reported, especially high. or combined with other acknowledged issues to cause a high severity issue.

In the case where SuperPool vault tokens are used as collateral in Positions, it is acceptable that liquidations don't go through during periods of high utilization because of lack of liquidity to service SuperPool redemptions
___

### Q: We will report issues where the core protocol functionality is inaccessible for at least 7 days. Would you like to override this value?
No
___

### Q: Please provide links to previous audits (if any).
1. https://github.com/sentimentxyz/protocol-v2/blob/master/audits/sentiment_v2_zobront.md

2. https://github.com/sentimentxyz/protocol-v2/blob/master/audits/sentiment_v2_guardian.pdf
___

### Q: Please list any relevant protocol resources.
https://docs.sentiment.xyz
___

### Q: Additional audit information.
Potentially vulnerable vectors:
- Stack precision errors and/or incorrect rounding direction
- Malicious interactions with PositionManager.process leading to failure states - blocked liquidations and bricking account operations
- AddToken and RemoveToken operations are not automatically called on accounts dynamically, the caller is expected to send them in at the right time.
- There’s no way to stop someone from sending assets directly to a position
- If a caller is able to have the account approve tokens for an unknown contract, it could cause a loss of funds
- Effects of L2 downtime or oracle non-performance on open positions
- Effects of rehypothecation: Base Pools could lend against SuperPool vault tokens

Forked Contracts
- ERC6909 was forked from solmate. increaseAllowance() and decreaseAllowance() functions were added as part of the last audit
- The SuperPool is heavily inspired from and modified from Yearn v3 and Metamorpho vault designs
___



### Q: On what chains are the smart contracts going to be deployed?
Any EVM-compatbile network
___

### Q: If you are integrating tokens, are you allowing only whitelisted tokens to work with the codebase or any complying with the standard? Are they assumed to have certain properties, e.g. be non-reentrant? Are there any types of [weird tokens](https://github.com/d-xo/weird-erc20) you want to integrate?
Tokens are whitelisted, only tokens with valid oracles can be used to create Base Pools.

Protocol governance will ensure that oracles are only set for standard ERC-20 tokens (plus USDC/USDT)
___

### Q: Are there any limitations on values set by admins (or other roles) in the codebase, including restrictions on array lengths?
Expected launch values for protocol params:
Min LTV = 10% = 100000000000000000
Max LTV = 98% = 980000000000000000
Min Debt = 0.05 ETH = 50000000000000000
Min Borrow = 0.05 ETH = 50000000000000000
Liquidation Fee = 0 (Might be increased to 20-30% in the future)
Liquidation Discount = 10% = 100000000000000000
Default Interest Fee = 10% = 100000000000000000
Default Origination Fee = 0
Sequencer Grace Period = 1 hour = 3600
Timelock Duration  = 24 hours (common across all contracts)
Timelock Deadline = 72 hours (common across all contracts)
MAX_QUEUE_LENGTH = 10
Max Position Assets = 5
Max Position Debt Pools = 5
___

### Q: Are there any limitations on values set by admins (or other roles) in protocols you integrate with, including restrictions on array lengths?
No.
___

### Q: For permissioned functions, please list all checks and requirements that will be made before calling the function.
All onlyOwner protocol functions will be controlled via a multisig, initially by the team and eventually by governance

All multisig operations will be simulated via Tenderly (or equivalent) before implementation
___

### Q: Is the codebase expected to comply with any EIPs? Can there be/are there any deviations from the specification?
SuperPool.sol is strictly ERC4626 compliant
Pool.sol is strictly ERC6909 compliant
___

### Q: Are there any off-chain mechanisms or off-chain procedures for the protocol (keeper bots, arbitrage bots, etc.)?
Liquidator bots: maintain protocol solvency through timely liquidation of risky positions
Reallocation bots: used to rebalance SuperPool deposits among respective base pools
___

### Q: Are there any hardcoded values that you intend to change before (some) deployments?
The following immutable might be modified before certain deployments:
Timelock Duration
Timelock Deadline
MAX_QUEUE_LENGTH
Max Position Assets
Max Position Debt Pools
___

### Q: If the codebase is to be deployed on an L2, what should be the behavior of the protocol in case of sequencer issues (if applicable)? Should Sherlock assume that the Sequencer won't misbehave, including going offline?
Issues due to sequencer going offline are valid only if they lead to a loss of funds and are not connected to price change risks.

Auditors can assume the sequencer is not overtly malicious.
___

### Q: Should potential issues, like broken assumptions about function behavior, be reported if they could pose risks in future integrations, even if they might not be an issue in the context of the scope? If yes, can you elaborate on properties/invariants that should hold?
No
___

### Q: Please discuss any design choices you made.
The deposit and withdraw flows in the SuperPool sequentially deposit and withdraw from pools. This can be inefficient at times. We assume that the SuperPool owner will use the reallocate function to rebalance liquidity among pools.

The purpose of bad debt liquidation is to ensure that the pool can revert back to a functional state after socialization of bad debt. It is expected that a small share of lenders might be able to withdraw funds before the function is executed.
___

### Q: Please list any known issues and explicitly state the acceptable risks for each known issue.
Previously acknowledged issues from past audits must be considered acceptable risks.

This condition can be overridden if a previously acknowledged issue can cause an issue of higher severity than reported, especially high. or combined with other acknowledged issues to cause a high severity issue.

In the case where SuperPool vault tokens are used as collateral in Positions, it is acceptable that liquidations don't go through during periods of high utilization because of lack of liquidity to service SuperPool redemptions
___

### Q: We will report issues where the core protocol functionality is inaccessible for at least 7 days. Would you like to override this value?
No
___

### Q: Please provide links to previous audits (if any).
1. https://github.com/sentimentxyz/protocol-v2/blob/master/audits/sentiment_v2_zobront.md

2. https://github.com/sentimentxyz/protocol-v2/blob/master/audits/sentiment_v2_guardian.pdf
___

### Q: Please list any relevant protocol resources.
https://docs.sentiment.xyz
___

### Q: Additional audit information.
Potentially vulnerable vectors:
- Stack precision errors and/or incorrect rounding direction
- Malicious interactions with PositionManager.process leading to failure states - blocked liquidations and bricking account operations
- AddToken and RemoveToken operations are not automatically called on accounts dynamically, the caller is expected to send them in at the right time.
- There’s no way to stop someone from sending assets directly to a position
- If a caller is able to have the account approve tokens for an unknown contract, it could cause a loss of funds
- Effects of L2 downtime or oracle non-performance on open positions
- Effects of rehypothecation: Base Pools could lend against SuperPool vault tokens

Forked Contracts
- ERC6909 was forked from solmate. increaseAllowance() and decreaseAllowance() functions were added as part of the last audit
- The SuperPool is heavily inspired from and modified from Yearn v3 and Metamorpho vault designs
___



# Audit scope


[protocol-v2 @ 04bf15565165396608cc0aedacf05897235518fd](https://github.com/sentimentxyz/protocol-v2/tree/04bf15565165396608cc0aedacf05897235518fd)
- [protocol-v2/src/Pool.sol](protocol-v2/src/Pool.sol)
- [protocol-v2/src/Position.sol](protocol-v2/src/Position.sol)
- [protocol-v2/src/PositionManager.sol](protocol-v2/src/PositionManager.sol)
- [protocol-v2/src/Registry.sol](protocol-v2/src/Registry.sol)
- [protocol-v2/src/RiskEngine.sol](protocol-v2/src/RiskEngine.sol)
- [protocol-v2/src/RiskModule.sol](protocol-v2/src/RiskModule.sol)
- [protocol-v2/src/SuperPool.sol](protocol-v2/src/SuperPool.sol)
- [protocol-v2/src/SuperPoolFactory.sol](protocol-v2/src/SuperPoolFactory.sol)
- [protocol-v2/src/irm/FixedRateModel.sol](protocol-v2/src/irm/FixedRateModel.sol)
- [protocol-v2/src/irm/KinkedRateModel.sol](protocol-v2/src/irm/KinkedRateModel.sol)
- [protocol-v2/src/irm/LinearRateModel.sol](protocol-v2/src/irm/LinearRateModel.sol)
- [protocol-v2/src/lib/ERC6909.sol](protocol-v2/src/lib/ERC6909.sol)
- [protocol-v2/src/lib/IterableSet.sol](protocol-v2/src/lib/IterableSet.sol)
- [protocol-v2/src/oracle/ChainlinkEthOracle.sol](protocol-v2/src/oracle/ChainlinkEthOracle.sol)
- [protocol-v2/src/oracle/ChainlinkUsdOracle.sol](protocol-v2/src/oracle/ChainlinkUsdOracle.sol)
- [protocol-v2/src/oracle/FixedPriceOracle.sol](protocol-v2/src/oracle/FixedPriceOracle.sol)
- [protocol-v2/src/oracle/RedstoneOracle.sol](protocol-v2/src/oracle/RedstoneOracle.sol)


