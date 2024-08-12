// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { BaseScript } from "./BaseScript.s.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { Pool } from "src/Pool.sol";
import { Position } from "src/Position.sol";
import { PositionManager } from "src/PositionManager.sol";
import { Registry } from "src/Registry.sol";
import { RiskEngine } from "src/RiskEngine.sol";
import { RiskModule } from "src/RiskModule.sol";
import { SuperPoolFactory } from "src/SuperPoolFactory.sol";
import { PortfolioLens } from "src/lens/PortfolioLens.sol";
import { SuperPoolLens } from "src/lens/SuperPoolLens.sol";

contract Deploy is BaseScript {
    // registry
    Registry public registry;
    // superpool factory
    SuperPoolFactory public superPoolFactory;
    // position manager
    address positionManagerImpl;
    PositionManager public positionManager;
    // risk
    RiskEngine public riskEngine;
    RiskModule public riskModule;
    // pool
    address poolImpl;
    Pool public pool;
    // position
    address public positionBeacon;
    // lens
    SuperPoolLens public superPoolLens;
    PortfolioLens public portfolioLens;

    struct DeployParams {
        address owner;
        address proxyAdmin;
        address feeRecipient;
        uint256 minLtv;
        uint256 maxLtv;
        uint256 minDebt;
        uint256 minBorrow;
        uint256 liquidationFee;
        uint256 liquidationDiscount;
        uint256 badDebtLiquidationDiscount;
        uint256 defaultInterestFee;
        uint256 defaultOriginationFee;
    }

    DeployParams params;

    // keccak(SENTIMENT_POSITION_MANAGER_KEY)
    bytes32 public constant SENTIMENT_POSITION_MANAGER_KEY =
        0xd4927490fbcbcafca716cca8e8c8b7d19cda785679d224b14f15ce2a9a93e148;
    // keccak(SENTIMENT_POOL_KEY)
    bytes32 public constant SENTIMENT_POOL_KEY = 0x1a99cbf6006db18a0e08427ff11db78f3ea1054bc5b9d48122aae8d206c09728;
    // keccak(SENTIMENT_RISK_ENGINE_KEY)
    bytes32 public constant SENTIMENT_RISK_ENGINE_KEY =
        0x5b6696788621a5d6b5e3b02a69896b9dd824ebf1631584f038a393c29b6d7555;
    // keccak(SENIMENT_POSITION_BEACON_KEY)
    bytes32 public constant SENTIMENT_POSITION_BEACON_KEY =
        0x6e7384c78b0e09fb848f35d00a7b14fc1ad10ae9b10117368146c0e09b6f2fa2;
    // keccak(SENTIMENT_RISK_MODULE_KEY)
    bytes32 public constant SENTIMENT_RISK_MODULE_KEY =
        0x881469d14b8443f6c918bdd0a641e9d7cae2592dc28a4f922a2c4d7ca3d19c77;

    function run() public {
        fetchParams();
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        _run();
        vm.stopBroadcast();
    }

    function runWithParams(DeployParams memory _params) public {
        params = _params;
        _run();
    }

    function _run() internal {
        // registry
        registry = new Registry();
        // risk
        riskEngine = new RiskEngine(address(registry), params.minLtv, params.maxLtv);
        riskEngine.transferOwnership(params.owner);
        riskModule = new RiskModule(address(registry), params.liquidationDiscount);
        // pool
        poolImpl = address(new Pool());
        bytes memory poolInitData = abi.encodeWithSelector(
            Pool.initialize.selector,
            params.owner,
            params.defaultInterestFee,
            params.defaultOriginationFee,
            address(registry),
            params.feeRecipient,
            params.minBorrow,
            params.minDebt
        );
        pool = Pool(address(new TransparentUpgradeableProxy(poolImpl, params.proxyAdmin, poolInitData)));
        // super pool factory
        superPoolFactory = new SuperPoolFactory(address(pool));
        // position manager
        positionManagerImpl = address(new PositionManager());
        bytes memory posmgrInitData = abi.encodeWithSelector(
            PositionManager.initialize.selector, params.owner, address(registry), params.liquidationFee
        );
        positionManager = PositionManager(
            address(new TransparentUpgradeableProxy(positionManagerImpl, params.proxyAdmin, posmgrInitData))
        );
        // position
        address positionImpl = address(new Position(address(pool), address(positionManager)));
        positionBeacon = address(new UpgradeableBeacon(positionImpl));
        // lens
        superPoolLens = new SuperPoolLens(address(pool), address(riskEngine));
        portfolioLens = new PortfolioLens(address(pool), address(riskEngine), address(positionManager));
        // register modules
        registry.setAddress(SENTIMENT_POSITION_MANAGER_KEY, address(positionManager));
        registry.setAddress(SENTIMENT_POOL_KEY, address(pool));
        registry.setAddress(SENTIMENT_RISK_ENGINE_KEY, address(riskEngine));
        registry.setAddress(SENTIMENT_POSITION_BEACON_KEY, address(positionBeacon));
        registry.setAddress(SENTIMENT_RISK_MODULE_KEY, address(riskModule));
        registry.transferOwnership(params.owner);
        // update module addresses
        pool.updateFromRegistry();
        positionManager.updateFromRegistry();
        riskEngine.updateFromRegistry();
        riskModule.updateFromRegistry();

        if (block.chainid != 31_337) generateLogs();
    }

    function fetchParams() internal {
        string memory config = getConfig();

        params.owner = vm.parseJsonAddress(config, "$.Deploy.owner");
        params.proxyAdmin = vm.parseJsonAddress(config, "$.Deploy.proxyAdmin");
        params.feeRecipient = vm.parseJsonAddress(config, "$.Deploy.feeRecipient");
        params.minLtv = vm.parseJsonUint(config, "$.Deploy.minLtv");
        params.maxLtv = vm.parseJsonUint(config, "$.Deploy.maxLtv");
        params.minDebt = vm.parseJsonUint(config, "$.Deploy.minDebt");
        params.minBorrow = vm.parseJsonUint(config, "$.Deploy.minBorrow");
        params.liquidationFee = vm.parseJsonUint(config, "$.Deploy.liquidationFee");
        params.liquidationDiscount = vm.parseJsonUint(config, "$.Deploy.liquidationDiscount");
        params.badDebtLiquidationDiscount = vm.parseJsonUint(config, "$.Deploy.badDebtLiquidationDiscount");
        params.defaultInterestFee = vm.parseJsonUint(config, "$.Deploy.defaultInterestFee");
        params.defaultOriginationFee = vm.parseJsonUint(config, "$.Deploy.defaultOriginationFee");

        require(params.owner != params.proxyAdmin, "OWNER == PROXY_ADMIN");
    }

    function generateLogs() internal {
        string memory obj = "Deploy";

        // deployed contracts
        vm.serializeAddress(obj, "registry", address(registry));
        vm.serializeAddress(obj, "superPoolFactory", address(superPoolFactory));
        vm.serializeAddress(obj, "positionManagerImpl", address(positionManagerImpl));
        vm.serializeAddress(obj, "positionManager", address(positionManager));
        vm.serializeAddress(obj, "riskEngine", address(riskEngine));
        vm.serializeAddress(obj, "riskModule", address(riskModule));
        vm.serializeAddress(obj, "poolImpl", address(poolImpl));
        vm.serializeAddress(obj, "pool", address(pool));
        vm.serializeAddress(obj, "positionBeacon", address(positionBeacon));
        vm.serializeAddress(obj, "superPoolLens", address(superPoolLens));
        vm.serializeAddress(obj, "portfolioLens", address(portfolioLens));

        // deployment params
        vm.serializeAddress(obj, "owner", params.owner);
        vm.serializeAddress(obj, "proxyAdmin", params.proxyAdmin);
        vm.serializeAddress(obj, "feeRecipient", params.feeRecipient);
        vm.serializeUint(obj, "minLtv", params.minLtv);
        vm.serializeUint(obj, "maxLtv", params.maxLtv);
        vm.serializeUint(obj, "minDebt", params.minDebt);
        vm.serializeUint(obj, "liquidationFee", params.liquidationFee);
        vm.serializeUint(obj, "liquidationDiscount", params.liquidationDiscount);

        // deployment details
        vm.serializeUint(obj, "chainId", block.chainid);
        string memory json = vm.serializeUint(obj, "timestamp", vm.getBlockTimestamp());

        string memory path = string.concat(getLogPathBase(), "Deploy-", vm.toString(vm.getBlockTimestamp()), ".json");
        vm.writeJson(json, path);
    }
}
