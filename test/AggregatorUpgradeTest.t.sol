// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../contracts/AggregatorLogic.sol";
import "../contracts/AggregatorLogicV2.sol";
import "../contracts/strategies/DexStrategyUniV2.sol";
import "../contracts/strategies/DexStrategyUniV3.sol";

address constant UNI_V2_ROUTER_MAINNET = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
address constant UNI_V3_QUOTER_MAINNET = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;
address constant UNI_V3_ROUTER_MAINNET = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

contract AggregatorUpgradeTest is Test {
    AggregatorLogic public aggregator;
    AggregatorLogicV2 public aggregatorV2;
    ProxyAdmin public proxyAdmin;
    TransparentUpgradeableProxy public proxy;
    address public proxyAdminAddress;

    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        
        // With OpenZeppelin 5.0+, we don't pre-deploy the ProxyAdmin
        AggregatorLogic logicImpl = new AggregatorLogic();
        bytes memory initData = abi.encodeWithSelector(logicImpl.initialize.selector);

        // Use address(this) as the initialOwner of the ProxyAdmin
        proxy = new TransparentUpgradeableProxy(
            address(logicImpl),
            address(this),  // initialOwner parameter - owner of the auto-deployed ProxyAdmin
            initData
        );
        
        // We need to find the ProxyAdmin address that was auto-created by the proxy
        // For testing purposes, we can get the storage slot where admin is stored
        // but in production, you would want to track the admin contract deployment
        bytes32 adminSlot = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
        proxyAdminAddress = address(uint160(uint256(vm.load(address(proxy), adminSlot))));
        proxyAdmin = ProxyAdmin(proxyAdminAddress);
        
        aggregator = AggregatorLogic(address(proxy));

        DexStrategyUniV2 v2Strategy = new DexStrategyUniV2(UNI_V2_ROUTER_MAINNET);
        DexStrategyUniV3 v3Strategy = new DexStrategyUniV3(
            UNI_V3_QUOTER_MAINNET,
            UNI_V3_ROUTER_MAINNET,
            3000
        );

        aggregator.setStrategy("UNISWAP_V2", address(v2Strategy));
        aggregator.setStrategy("UNISWAP_V3", address(v3Strategy));
    }

    function testUpgradeToV2() public {
        // 1. Try to call getDexNames on V1 - should fail
        // We need to use a low-level call since the method doesn't exist in the interface
        (bool success, ) = address(aggregator).call(
            abi.encodeWithSignature("getDexNames()")
        );
        assertFalse(success, "getDexNames should fail on V1");

        // 2. Deploy V2 implementation
        AggregatorLogicV2 logicImplV2 = new AggregatorLogicV2();

        // 3. (NEW) Upgrade and call any required initializer for V2
        // If there's no new initializer, just pass an empty bytes array:
        //    bytes memory data = bytes("");
        // Otherwise, encode the initializer, e.g. "initializeV2()" below:
        bytes memory data = abi.encodeWithSignature("initializeV2()");

        // Cast the proxy to the ITransparentUpgradeableProxy interface as required
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(proxy)),
            address(logicImplV2),
            data
        );

        // 4. Cast proxy to V2
        aggregatorV2 = AggregatorLogicV2(address(proxy));

        // 5. Verify we can call getDexNames and it returns correct values
        string[] memory dexNames = aggregatorV2.getDexNames();
        assertEq(dexNames.length, 2, "Should have 2 DEX names");

        // 6. Verify old functionality still works
        assertEq(aggregatorV2.getDexCount(), 2, "DEX count should still be 2");
    }
} 