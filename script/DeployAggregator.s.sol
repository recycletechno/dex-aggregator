// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
// OpenZeppelin's proxy admin + transparent proxy
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

// The aggregator logic (upgradeable)
import "../contracts/AggregatorLogic.sol";

// Strategies
import "../contracts/strategies/DexStrategyUniV2.sol";
import "../contracts/strategies/DexStrategyUniV3.sol";

/**
 * @dev Foundry script to deploy aggregator + strategies on Ethereum mainnet 
 *      using OpenZeppelin's TransparentUpgradeableProxy.
 *
 * Usage:
 *   forge script script/DeployAggregator.s.sol 
 *       --fork-url http://localhost:8545
 *       --private-key $PRIVATE_KEY
 *       --broadcast
 *
 *   forge script script/DeployAggregator.s.sol \
 *       --rpc-url $ETH_RPC_URL \
 *       --private-key $PRIVATE_KEY \
 *       --broadcast
 */
contract DeployAggregator is Script {
    // Uniswap v2 mainnet router
    address constant UNI_V2_ROUTER      = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    // Uniswap v3 mainnet quoter & swap
    address constant UNI_V3_QUOTER      = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;
    address constant UNI_V3_SWAPROUTER  = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    function run() external {
        vm.startBroadcast();

        // 1) Deploy the ProxyAdmin (the admin that can upgrade the proxy)
        ProxyAdmin proxyAdmin = new ProxyAdmin(msg.sender);

        // 2) Deploy the aggregator logic (implementation)
        AggregatorLogic aggregatorLogicImpl = new AggregatorLogic();

        // 3) Initialize data: call aggregatorLogicImpl.initialize() after proxy is set
        bytes memory initData = abi.encodeWithSelector(
            aggregatorLogicImpl.initialize.selector
            // pass constructor-like args if needed
        );

        // 4) Deploy the TransparentUpgradeableProxy
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(aggregatorLogicImpl), 
            address(proxyAdmin), 
            initData
        );

        // The aggregator "interface" is the proxy address
        AggregatorLogic aggregator = AggregatorLogic(address(proxy));

        // 5) Deploy strategies (same as before)
        DexStrategyUniV2 uniV2Strategy = new DexStrategyUniV2(UNI_V2_ROUTER);
        DexStrategyUniV3 uniV3Strategy = new DexStrategyUniV3(UNI_V3_QUOTER, UNI_V3_SWAPROUTER, 3000);

        // 6) Since aggregator is OwnableUpgradeable, we (currently msg.sender) are the owner
        aggregator.setStrategy("UNISWAP_V2", address(uniV2Strategy));
        aggregator.setStrategy("UNISWAP_V3", address(uniV3Strategy));

        vm.stopBroadcast();
    }
}
