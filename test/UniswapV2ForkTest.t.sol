// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol";

// Uniswap V2 Router interface
interface IUniswapV2Router02 {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);
}

contract UniswapV2ForkTest is Test {
    // Mainnet addresses
    address constant UNI_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    
    // WETH whale address
    address constant WETH_WHALE = 0xF04a5cC80B1E94C69B48f5ee68a08CD2F09A7c3E;

    IUniswapV2Router02 public router;
    IERC20 public weth;
    IERC20 public usdc;

    function setUp() public {
        // Fork mainnet
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        
        // Initialize contracts
        router = IUniswapV2Router02(UNI_V2_ROUTER);
        weth = IERC20(WETH);
        usdc = IERC20(USDC);
    }

    function testDirectSwap() public {
        // Impersonate WETH whale
        vm.startPrank(WETH_WHALE);

        // Amount to swap
        uint256 amountIn = 0.1e18; // 0.1 WETH
        
        // Get quote
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = USDC;
        
        uint256[] memory amounts = router.getAmountsOut(amountIn, path);
        uint256 expectedOut = amounts[1];
        
        // Calculate minimum output with 2% slippage
        uint256 minAmountOut = (expectedOut * 98) / 100;
        
        // Approve router to spend WETH
        weth.approve(address(router), amountIn);
        
        // Get initial USDC balance
        uint256 initialUsdcBalance = usdc.balanceOf(WETH_WHALE);
        
        // Execute swap
        router.swapExactTokensForTokens(
            amountIn,
            minAmountOut,
            path,
            WETH_WHALE,
            block.timestamp + 120
        );
        
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