// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                        SuperPoolFactory
//////////////////////////////////////////////////////////////*/

import { SuperPool } from "./SuperPool.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title SuperPoolFactory
/// @notice Factory for creating SuperPools, which act as aggregators over individual pools
/// @dev A new factory must be deployed if the SuperPool implementation is upgraded
contract SuperPoolFactory {
    using SafeERC20 for IERC20;

    address private constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    /// @notice Minimum amount of initial shares to be burned
    uint256 public constant MIN_BURNED_SHARES = 1000;

    /// @notice All Pools exist on the Singleton Pool Contract, which is fixed per factory
    address public immutable POOL;

    /// @notice Verify if a particular SuperPool was deployed by this factory
    mapping(address superPool => bool isDeployer) public isDeployerFor;

    /// @notice New Super Pool instance was deployed
    event SuperPoolDeployed(address indexed owner, address superPool, address asset, string name, string symbol);

    /// @notice SuperPools with non-zero fees cannot have an address(0) fee recipient
    error SuperPoolFactory_ZeroFeeRecipient();
    /// @notice Amount of initial shares burned is too low
    error SuperPoolFactory_TooFewInitialShares(uint256 initialShares);

    /// @param _pool The address of the pool contract
    constructor(address _pool) {
        POOL = _pool;
    }

    // SuperPool deployment flow:
    // 1. Deploy a new superpool as a transparent proxy using the factory impl
    // 2. Transfer superpool ownership to the specified owner
    // 3. Emit SuperPool creation log
    // 4. Return the address to the newly deployed SuperPool

    /// @notice Deploy a new SuperPool
    /// @param owner Owner of the SuperPool, and tasked with allocation and adjusting Pool Caps
    /// @param asset The asset to be deposited in the SuperPool
    /// @param feeRecipient The address to initially receive the fee
    /// @param fee The fee, out of 1e18, taken from interest earned
    /// @param superPoolCap The maximum amount of assets that can be deposited in the SuperPool
    /// @param initialDepositAmt Initial amount of assets, deposited into the superpool and burned
    /// @param name The name of the SuperPool
    /// @param symbol The symbol of the SuperPool
    function deploySuperPool(
        address owner,
        address asset,
        address feeRecipient,
        uint256 fee,
        uint256 superPoolCap,
        uint256 initialDepositAmt,
        string calldata name,
        string calldata symbol
    ) external returns (address) {
        if (fee != 0 && feeRecipient == address(0)) revert SuperPoolFactory_ZeroFeeRecipient();
        SuperPool superPool = new SuperPool(POOL, asset, feeRecipient, fee, superPoolCap, name, symbol);
        superPool.transferOwnership(owner);
        isDeployerFor[address(superPool)] = true;

        // burn initial deposit
        IERC20(asset).safeTransferFrom(msg.sender, address(this), initialDepositAmt); // assume approval
        IERC20(asset).approve(address(superPool), initialDepositAmt);
        uint256 shares = superPool.deposit(initialDepositAmt, address(this));
        if (shares < MIN_BURNED_SHARES) revert SuperPoolFactory_TooFewInitialShares(shares);
        IERC20(superPool).transfer(DEAD_ADDRESS, shares);

        emit SuperPoolDeployed(owner, address(superPool), asset, name, symbol);
        return address(superPool);
    }
}
