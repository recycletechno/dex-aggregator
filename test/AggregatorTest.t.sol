// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import "openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "../contracts/AggregatorLogic.sol";
import "../contracts/strategies/DexStrategyUniV2.sol";
import "../contracts/strategies/DexStrategyUniV3.sol";

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol";


address constant UNI_V2_ROUTER_MAINNET = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D; 
address constant UNI_V3_QUOTER_MAINNET = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;
address constant UNI_V3_ROUTER_MAINNET = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

address constant WETH_MAINNET = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
address constant USDC_MAINNET = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);


contract AggregatorTest is Test {
    AggregatorLogic public aggregator;
    ProxyAdmin public proxyAdmin;

    function setUp() public {
        // 1) Fork mainnet
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        
        // 2) Deploy aggregator logic + proxy
        proxyAdmin = new ProxyAdmin(address(this));
        AggregatorLogic logicImpl = new AggregatorLogic();
        bytes memory initData = abi.encodeWithSelector(logicImpl.initialize.selector);

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(logicImpl),
            address(proxyAdmin),
            initData
        );
        aggregator = AggregatorLogic(address(proxy));

        // 3) Deploy real strategies
        DexStrategyUniV2 v2Strategy = new DexStrategyUniV2(UNI_V2_ROUTER_MAINNET);
        DexStrategyUniV3 v3Strategy = new DexStrategyUniV3(
            UNI_V3_QUOTER_MAINNET,
            UNI_V3_ROUTER_MAINNET,
            3000  // 0.3% fee tier, we can iterate on list of fee tiers
        );

        aggregator.setStrategy("UNISWAP_V2", address(v2Strategy));
        aggregator.setStrategy("UNISWAP_V3", address(v3Strategy));
    }

    function testGetQuote() public {
        // Get a quote for swapping 1 ETH -> USDC via aggregator
        uint256 amountIn = 1e18; // 1 ETH
        (bytes32 bestDex, uint256 bestQuote) = aggregator.getBestQuote(
            WETH_MAINNET,
            USDC_MAINNET,
            amountIn
        );
        console.log("Best DEX:", string(abi.encodePacked(bestDex)));
        console.log("Best USDC out raw:", bestQuote);
        assertTrue(bestQuote > 0, "Should have a positive quote");
    }

    function testRealSwap() public {

        address whale = 0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E;
        vm.startPrank(whale);

        uint256 swapAmount = 0.1e18; // 0.1 WETH

        (bytes32 bestDex, uint256 expectedOut) = aggregator.getBestQuote(
            WETH_MAINNET,
            USDC_MAINNET,
            swapAmount
        );
        
        // 2% slippage
        uint256 minAmountOut = (expectedOut * 98) / 100;

        uint256 initialWethBalance = IERC20(WETH_MAINNET).balanceOf(whale);
        uint256 initialUsdcBalance = IERC20(USDC_MAINNET).balanceOf(whale);

        IERC20(WETH_MAINNET).approve(address(aggregator), swapAmount);

        aggregator.swap(
            WETH_MAINNET,
            USDC_MAINNET,
            swapAmount,
            minAmountOut,
            whale
        );

        uint256 finalWethBalance = IERC20(WETH_MAINNET).balanceOf(whale);
        uint256 finalUsdcBalance = IERC20(USDC_MAINNET).balanceOf(whale);

        assertTrue(finalWethBalance < initialWethBalance, "WETH balance should decrease");
        assertTrue(finalUsdcBalance > initialUsdcBalance, "USDC balance should increase");
        assertTrue(finalUsdcBalance >= minAmountOut, "Should receive at least minimum amount");

        console.log("Best DEX:", string(abi.encodePacked(bestDex)));
        console.log("Initial WETH balance:", initialWethBalance);
        console.log("Final WETH balance:", finalWethBalance);
        console.log("Initial USDC balance:", initialUsdcBalance);
        console.log("Final USDC balance:", finalUsdcBalance);
        console.log("Minimum expected USDC:", minAmountOut);

        vm.stopPrank();
    }

    function testAddingNewDex() public {
        // 1) Fork mainnet
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        
        // 2) Deploy aggregator logic + proxy
        proxyAdmin = new ProxyAdmin(address(this));
        AggregatorLogic logicImpl = new AggregatorLogic();
        bytes memory initData = abi.encodeWithSelector(logicImpl.initialize.selector);

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(logicImpl),
            address(proxyAdmin),
            initData
        );
        aggregator = AggregatorLogic(address(proxy));

        // 3) Deploy and add only Uniswap V2 strategy initially
        DexStrategyUniV2 v2Strategy = new DexStrategyUniV2(UNI_V2_ROUTER_MAINNET);
        aggregator.setStrategy("UNISWAP_V2", address(v2Strategy));
        
        // 4) Verify that getDexCount() returns 1
        uint256 dexCount = aggregator.getDexCount();
        assertEq(dexCount, 1, "Should have exactly 1 DEX after adding Uniswap V2");
        console.log("Dex count after adding Uniswap V2:", dexCount);
        
        // 5) Now deploy and add Uniswap V3 strategy
        DexStrategyUniV3 v3Strategy = new DexStrategyUniV3(
            UNI_V3_QUOTER_MAINNET,
            UNI_V3_ROUTER_MAINNET,
            3000  // 0.3% fee tier
        );
        aggregator.setStrategy("UNISWAP_V3", address(v3Strategy));
        
        // 6) Verify that getDexCount() now returns 2
        dexCount = aggregator.getDexCount();
        assertEq(dexCount, 2, "Should have exactly 2 DEXes after adding Uniswap V3");
        console.log("Dex count after adding Uniswap V3:", dexCount);
        
        // 7) Verify that both DEXes are used in getBestQuote
        uint256 amountIn = 1e18; // 1 ETH
        (bytes32 bestDex, uint256 bestQuote) = aggregator.getBestQuote(
            WETH_MAINNET,
            USDC_MAINNET,
            amountIn
        );
        assertTrue(bestQuote > 0, "Should have a positive quote");
        console.log("Best DEX after adding both:", string(abi.encodePacked(bestDex)));
    }
}
