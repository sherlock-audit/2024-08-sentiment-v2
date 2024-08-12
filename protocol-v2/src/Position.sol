// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                            Position
//////////////////////////////////////////////////////////////*/

import { Pool } from "./Pool.sol";
import { IterableSet } from "./lib/IterableSet.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Position
contract Position {
    using SafeERC20 for IERC20;
    using IterableSet for IterableSet.AddressSet;
    using IterableSet for IterableSet.Uint256Set;

    /// @notice Position implementation version
    uint256 public constant VERSION = 1;

    /// @notice Maximum number of assets that a position can hold at once
    uint256 public constant MAX_ASSETS = 5;
    /// @notice Maximum number of pools that a position can borrow from at once
    uint256 public constant MAX_DEBT_POOLS = 5;

    /// @notice Sentiment Pool
    Pool public immutable POOL;
    /// @notice Sentiment Position Manager
    address public immutable POSITION_MANAGER;

    /// @dev Iterable uint256 set that stores pool ids with active borrows
    IterableSet.Uint256Set internal debtPools;
    /// @dev Iterable address set that stores assets held by the position
    IterableSet.AddressSet internal positionAssets;

    /// @notice Number of assets held by the position exceeds `MAX_ASSETS`
    error Position_MaxAssetsExceeded(address position);
    /// @notice Number of pools with active borrows exceeds `MAX_DEBT_POOLS`
    error Position_MaxDebtPoolsExceeded(address position);
    /// @notice Exec operation on the position returned false
    error Position_ExecFailed(address position, address target);
    /// @notice Function access restricted to Sentiment Position Manager
    error Position_OnlyPositionManager(address position, address sender);

    /// @param pool Sentiment Singleton Pool
    /// @param positionManager Sentiment Postion Manager
    constructor(address pool, address positionManager) {
        POOL = Pool(pool);
        POSITION_MANAGER = positionManager;
    }

    // positions can receive and hold ether to perform external operations.
    // ether is otherwise ignored by the rest of the protocol. it does not count
    // towards the position balance, pools cannot lend ether and it cannot be
    // used as collateral to borrow other assets
    receive() external payable { }

    modifier onlyPositionManager() {
        if (msg.sender != POSITION_MANAGER) revert Position_OnlyPositionManager(address(this), msg.sender);
        _;
    }

    /// @notice Fetch list of pool ids with active borrows to the position
    function getDebtPools() external view returns (uint256[] memory) {
        return debtPools.getElements();
    }

    /// @notice Fetch list of assets currently held by the position
    function getPositionAssets() external view returns (address[] memory) {
        return positionAssets.getElements();
    }

    /// @notice Check if a given asset exists in the position asset set
    /// @dev an asset with zero balance could be in the set until explicitly removed
    function hasAsset(address asset) external view returns (bool) {
        return positionAssets.contains(asset);
    }

    /// @notice Check if a given debt pool exists in the debt pool set
    /// @dev Position.repay() removes the debt pool after complete repayment
    function hasDebt(uint256 poolId) external view returns (bool) {
        return debtPools.contains(poolId);
    }

    /// @notice Approve an external contract to spend funds from the position
    /// @dev The position manager imposes additional checks that the spender is trusted
    function approve(address token, address spender, uint256 amt) external onlyPositionManager {
        // use forceApprove to handle tokens with non-standard return values
        // and tokens that force setting allowance to zero before modification
        IERC20(token).forceApprove(spender, amt);
    }

    /// @notice Transfer assets from a position to a given external address
    /// @dev Any additional checks must be implemented in the position manager
    function transfer(address to, address asset, uint256 amt) external onlyPositionManager {
        // handle tokens with non-standard return values using safeTransfer
        IERC20(asset).safeTransfer(to, amt);
    }

    /// @notice Intereact with external contracts using arbitrary calldata
    /// @dev Target and calldata is validated by the position manager
    function exec(address target, uint256 value, bytes calldata data) external onlyPositionManager {
        (bool success,) = target.call{ value: value }(data);
        if (!success) revert Position_ExecFailed(address(this), target);
    }

    /// @notice Add asset to the list of tokens currently held by the position
    function addToken(address asset) external onlyPositionManager {
        positionAssets.insert(asset);
        if (positionAssets.length() > MAX_ASSETS) revert Position_MaxAssetsExceeded(address(this));
    }

    /// @notice Remove asset from the list of tokens currrently held by the position
    function removeToken(address asset) external onlyPositionManager {
        positionAssets.remove(asset);
    }

    /// @notice Signal that the position has borrowed from a given pool
    /// @dev Position assumes that this is done after debt assets have been transferred and
    ///      Pool.borrow() has already been called
    function borrow(uint256 poolId, uint256) external onlyPositionManager {
        debtPools.insert(poolId);
        if (debtPools.length() > MAX_DEBT_POOLS) revert Position_MaxDebtPoolsExceeded(address(this));
    }

    /// @notice Signal that the position has repaid debt to a given pool
    /// @dev Position assumes that this is done after debt assets have been transferred and
    ///      Pool.repay() has been called so the pool can be removed from `debtPools` as needed
    function repay(uint256 poolId, uint256) external onlyPositionManager {
        if (POOL.getBorrowsOf(poolId, address(this)) == 0) debtPools.remove(poolId);
    }
}
