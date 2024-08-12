// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Deploy } from "../script/Deploy.s.sol";
import { FixedRateModel } from "../src/irm/FixedRateModel.sol";
import { LinearRateModel } from "../src/irm/LinearRateModel.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockSwap } from "./mocks/MockSwap.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";
import { Pool } from "src/Pool.sol";
import { Position } from "src/Position.sol";
import { PositionManager } from "src/PositionManager.sol";
import { Action, Operation, PositionManager } from "src/PositionManager.sol";
import { Registry } from "src/Registry.sol";
import { RiskEngine } from "src/RiskEngine.sol";
import { RiskModule } from "src/RiskModule.sol";
import { SuperPool } from "src/SuperPool.sol";
import { SuperPoolFactory } from "src/SuperPoolFactory.sol";
import { PortfolioLens } from "src/lens/PortfolioLens.sol";
import { SuperPoolLens } from "src/lens/SuperPoolLens.sol";
import { FixedPriceOracle } from "src/oracle/FixedPriceOracle.sol";

contract BaseTest is Test {
    address public user = makeAddr("user");
    address public user2 = makeAddr("user2");
    address public lender = makeAddr("lender");
    address public poolOwner = makeAddr("poolOwner");
    address public proxyAdmin = makeAddr("proxyAdmin");
    address public protocolOwner = makeAddr("protocolOwner");

    MockERC20 public asset1;
    MockERC20 public asset2;
    MockERC20 public asset3;

    MockSwap public mockswap;
    bytes4 public constant SWAP_FUNC_SELECTOR =
        bytes4(bytes32(0xdf791e5000000000000000000000000000000000000000000000000000000000));

    uint256 public fixedRatePool;
    uint256 public linearRatePool;
    uint256 public fixedRatePool2;
    uint256 public linearRatePool2;
    uint256 public alternateAssetPool;

    Deploy public protocol;

    function setUp() public virtual {
        Deploy.DeployParams memory params = Deploy.DeployParams({
            owner: protocolOwner,
            proxyAdmin: proxyAdmin,
            feeRecipient: address(this),
            minLtv: 2e17, // 0.1
            maxLtv: 8e17, // 0.8
            minDebt: 0,
            minBorrow: 0,
            liquidationFee: 0,
            liquidationDiscount: 200_000_000_000_000_000,
            badDebtLiquidationDiscount: 1e16,
            defaultOriginationFee: 0,
            defaultInterestFee: 0
        });

        protocol = new Deploy();
        protocol.runWithParams(params);

        asset1 = new MockERC20("Asset1", "ASSET1", 18);
        asset2 = new MockERC20("Asset2", "ASSET2", 18);
        asset3 = new MockERC20("Asset3", "ASSET3", 18);

        mockswap = new MockSwap();

        vm.startPrank(protocolOwner);
        protocol.positionManager().toggleKnownAsset(address(asset1));
        protocol.positionManager().toggleKnownAsset(address(asset2));
        protocol.positionManager().toggleKnownAsset(address(asset3));
        protocol.positionManager().toggleKnownSpender(address(mockswap));
        protocol.positionManager().toggleKnownFunc(address(mockswap), SWAP_FUNC_SELECTOR);
        vm.stopPrank();

        FixedPriceOracle testOracle = new FixedPriceOracle(1e18);
        vm.startPrank(protocolOwner);
        protocol.riskEngine().setOracle(address(asset1), address(testOracle));
        protocol.riskEngine().setOracle(address(asset2), address(testOracle));
        vm.stopPrank();

        address fixedRateModel = address(new FixedRateModel(1e18));
        address linearRateModel = address(new LinearRateModel(1e18, 2e18));
        address fixedRateModel2 = address(new FixedRateModel(2e18));
        address linearRateModel2 = address(new LinearRateModel(2e18, 3e18));

        bytes32 FIXED_RATE_MODEL_KEY = 0xeba2c14de8b8ca05a15d7673453a0a3b315f122f56770b8bb643dc4bfbcf326b;
        bytes32 LINEAR_RATE_MODEL_KEY = 0x7922391f605f567c8e61c33be42b581e2f71019b5dce3c47110ad332b7dbd68c;
        bytes32 FIXED_RATE_MODEL2_KEY = 0x65347a20305cbd3ca20cb81ec8a2261639f4e635b4b5f3039a9aa5e7e03f41a7;
        bytes32 LINEAR_RATE_MODEL2_KEY = 0xd61dc960093d99acc135f998430c41a550d91de727e66a94fd8e7a8a24d99ecf;

        vm.startPrank(protocolOwner);
        Registry(protocol.registry()).setRateModel(FIXED_RATE_MODEL_KEY, fixedRateModel);
        Registry(protocol.registry()).setRateModel(LINEAR_RATE_MODEL_KEY, linearRateModel);
        Registry(protocol.registry()).setRateModel(FIXED_RATE_MODEL2_KEY, fixedRateModel2);
        Registry(protocol.registry()).setRateModel(LINEAR_RATE_MODEL2_KEY, linearRateModel2);
        vm.stopPrank();

        vm.startPrank(poolOwner);
        fixedRatePool =
            protocol.pool().initializePool(poolOwner, address(asset1), type(uint128).max, FIXED_RATE_MODEL_KEY);
        linearRatePool =
            protocol.pool().initializePool(poolOwner, address(asset1), type(uint128).max, LINEAR_RATE_MODEL_KEY);
        fixedRatePool2 =
            protocol.pool().initializePool(poolOwner, address(asset1), type(uint128).max, FIXED_RATE_MODEL2_KEY);
        linearRatePool2 =
            protocol.pool().initializePool(poolOwner, address(asset1), type(uint128).max, LINEAR_RATE_MODEL2_KEY);
        alternateAssetPool =
            protocol.pool().initializePool(poolOwner, address(asset2), type(uint128).max, FIXED_RATE_MODEL_KEY);
        vm.stopPrank();
    }

    function newPosition(address owner, bytes32 salt) internal view returns (address payable, Action memory) {
        bytes memory data = abi.encodePacked(owner, salt);
        (address position,) = protocol.portfolioLens().predictAddress(owner, salt);
        Action memory action = Action({ op: Operation.NewPosition, data: data });
        return (payable(position), action);
    }

    function deposit(address asset, uint256 amt) internal pure returns (Action memory) {
        bytes memory data = abi.encodePacked(asset, amt);
        Action memory action = Action({ op: Operation.Deposit, data: data });
        return action;
    }

    function addToken(address asset) internal pure returns (Action memory) {
        bytes memory data = abi.encodePacked(asset);
        Action memory action = Action({ op: Operation.AddToken, data: data });
        return action;
    }

    function removeToken(address asset) internal pure returns (Action memory) {
        bytes memory data = abi.encodePacked(asset);
        Action memory action = Action({ op: Operation.RemoveToken, data: data });
        return action;
    }

    function borrow(uint256 poolId, uint256 amt) internal pure returns (Action memory) {
        bytes memory data = abi.encodePacked(poolId, amt);
        Action memory action = Action({ op: Operation.Borrow, data: data });
        return action;
    }

    function approve(address spender, address asset, uint256 amt) internal pure returns (Action memory) {
        bytes memory data = abi.encodePacked(spender, asset, amt);
        Action memory action = Action({ op: Operation.Approve, data: data });
        return action;
    }

    function transfer(address recipient, address asset, uint256 amt) internal pure returns (Action memory) {
        bytes memory data = abi.encodePacked(recipient, asset, amt);
        Action memory action = Action({ op: Operation.Transfer, data: data });
        return action;
    }

    function exec(address target, uint256 value, bytes memory execData) internal pure returns (Action memory) {
        bytes memory data = abi.encodePacked(target, value, execData);
        Action memory action = Action({ op: Operation.Exec, data: data });
        return action;
    }
}
