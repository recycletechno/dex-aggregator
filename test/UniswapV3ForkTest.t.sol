// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol";

// Uniswap V3 Router interface
interface IUniswapV3Router {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        returns (uint256 amountOut);
}

interface IUniswapV3Quoter {
    function quoteExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256 amountOut);
}

contract UniswapV3ForkTest is Test {
    // Mainnet addresses
    address constant UNI_V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant UNI_V3_QUOTER = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    
    // WETH whale address
    address constant WETH_WHALE = 0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E;

    IUniswapV3Router public router;
    IUniswapV3Quoter public quoter;
    IERC20 public weth;
    IERC20 public usdc;

    function setUp() public {
        // Fork mainnet
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        
        // Initialize contracts
        router = IUniswapV3Router(UNI_V3_ROUTER);
        quoter = IUniswapV3Quoter(UNI_V3_QUOTER);
        weth = IERC20(WETH);
        usdc = IERC20(USDC);
    }

    function testDirectSwap() public {
        // Impersonate WETH whale
        vm.startPrank(WETH_WHALE);

        // Amount to swap
        uint256 amountIn = 0.1e18; // 0.1 WETH
        
        // Get quote
        uint256 expectedOut = quoter.quoteExactInputSingle(
            WETH,
            USDC,
            3000, // 0.3% fee tier
            amountIn,
            0
        );
        
        // Calculate minimum output with 2% slippage
        uint256 minAmountOut = (expectedOut * 98) / 100;
        
        // Approve router to spend WETH
        weth.approve(address(router), amountIn);
        
        // Get initial USDC balance
        uint256 initialUsdcBalance = usdc.balanceOf(WETH_WHALE);
        
        // Execute swap
        IUniswapV3Router.ExactInputSingleParams memory params = IUniswapV3Router.ExactInputSingleParams({
            tokenIn: WETH,
            tokenOut: USDC,
            fee: 3000, // 0.3% fee tier
            recipient: WETH_WHALE,
            deadline: block.timestamp + 120,
            amountIn: amountIn,
            amountOutMinimum: minAmountOut,
            sqrtPriceLimitX96: 0
        });

        router.exactInputSingle(params);
        
        // Get final USDC balance
        uint256 finalUsdcBalance = usdc.balanceOf(WETH_WHALE);
        
        // Verify USDC balance increased
        assertTrue(finalUsdcBalance > initialUsdcBalance, "USDC balance should increase");
        assertTrue(finalUsdcBalance >= minAmountOut, "Should receive at least minimum amount");
        
        console.log("Initial USDC balance:", initialUsdcBalance);
        console.log("Final USDC balance:", finalUsdcBalance);
        console.log("Minimum expected USDC:", minAmountOut);
        
        vm.stopPrank();
    }
} 