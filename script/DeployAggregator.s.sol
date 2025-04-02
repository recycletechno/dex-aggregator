// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../contracts/AggregatorLogic.sol";
import "../contracts/strategies/DexStrategyUniV2.sol";
import "../contracts/strategies/DexStrategyUniV3.sol";

/**
 * @dev Deploy the Aggregator contract
 * Usage:
 *   anvil --fork-url $ETH_RPC_URL
 *   forge script script/DeployAggregator.s.sol --fork-url http://localhost:8545 --private-key $PRIVATE_KEY --broadcast -v
 *   cast call {AggregatorLogic address} "getDexCount()(uint256)" --rpc-url http://localhost:8545
 */
contract DeployAggregator is Script {
    address constant UNI_V2_ROUTER      = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address constant UNI_V3_QUOTER      = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;
    address constant UNI_V3_SWAPROUTER  = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    function run() external {
        vm.startBroadcast();

        // 1) Deploy the ProxyAdmin
        ProxyAdmin proxyAdmin = new ProxyAdmin(msg.sender);
        console.log("ProxyAdmin deployed at:", address(proxyAdmin));

        // 2) Deploy the aggregator logic (implementation)
        AggregatorLogic aggregatorLogicImpl = new AggregatorLogic();
        console.log("AggregatorLogic implementation deployed at:", address(aggregatorLogicImpl));

        // 3) Initialize data: call aggregatorLogicImpl.initialize() after proxy is set
        bytes memory initData = abi.encodeWithSelector(
            aggregatorLogicImpl.initialize.selector
        );

        // 4) Deploy the TransparentUpgradeableProxy
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(aggregatorLogicImpl), 
            address(proxyAdmin), 
            initData
        );
        console.log("TransparentUpgradeableProxy (main Aggregator contract) deployed at:", address(proxy));

        // The aggregator "interface" is the proxy address
        AggregatorLogic aggregator = AggregatorLogic(address(proxy));

        // 5) Deploy strategies (same as before)
        DexStrategyUniV2 uniV2Strategy = new DexStrategyUniV2(UNI_V2_ROUTER);
        console.log("UniswapV2 Strategy deployed at:", address(uniV2Strategy));
        
        DexStrategyUniV3 uniV3Strategy = new DexStrategyUniV3(UNI_V3_QUOTER, UNI_V3_SWAPROUTER, 3000);
        console.log("UniswapV3 Strategy deployed at:", address(uniV3Strategy));

        // 6) Since aggregator is OwnableUpgradeable, we (currently msg.sender) are the owner
        aggregator.setStrategy("UNISWAP_V2", address(uniV2Strategy));
        aggregator.setStrategy("UNISWAP_V3", address(uniV3Strategy));
        
        console.log("Deployment completed. To check DEX count, run:");
        console.log("cast call", address(proxy), "\"getDexCount()(uint256)\"", "--rpc-url http://localhost:8545");

        vm.stopBroadcast();
    }
}
