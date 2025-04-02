// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../interfaces/IDexStrategy.sol";
import "../interfaces/IUniswapV3Quoter.sol";
import "../interfaces/IUniswapV3SwapRouter.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/**
 * @dev Strategy that uses Uniswap v3 Quoter + SwapRouter on Ethereum mainnet.
 *        Quoter:     0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6
 *        SwapRouter: 0xE592427A0AEce92De3Edee1F18E0157C05861564
 */
contract DexStrategyUniV3 is IDexStrategy {
    using SafeERC20 for IERC20;

    IUniswapV3Quoter public immutable quoter;
    IUniswapV3SwapRouter public immutable swapRouter;
    uint24 public immutable feeTier; // e.g. 3000 = 0.3%

    constructor(
        address _quoter,
        address _swapRouter,
        uint24 _feeTier
    ) {
        require(_quoter != address(0), "Invalid quoter");
        require(_swapRouter != address(0), "Invalid router");
        quoter = IUniswapV3Quoter(_quoter);
        swapRouter = IUniswapV3SwapRouter(_swapRouter);
        feeTier = _feeTier;
    }

    function getQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external virtual override returns (uint256 amountOut) {
        if (amountIn == 0 || tokenIn == tokenOut) {
            return 0;
        }

        try quoter.quoteExactInputSingle(
            tokenIn,
            tokenOut,
            feeTier,
            amountIn,
            0
        ) returns (uint256 quotedAmountOut) {
            amountOut = quotedAmountOut;
        } catch {
            amountOut = 0;
        }
    }

    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient
    ) external virtual override returns (uint256 amountOut) {
        require(tokenIn != tokenOut, "Same token");
        require(amountIn > 0, "No input tokens");

        IERC20(tokenIn).safeIncreaseAllowance(address(swapRouter), amountIn);

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        IUniswapV3SwapRouter.ExactInputSingleParams memory params = IUniswapV3SwapRouter
            .ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: feeTier,
                recipient: recipient,
                deadline: block.timestamp + 120,
                amountIn: amountIn,
                amountOutMinimum: minAmountOut,
                sqrtPriceLimitX96: 0
            });

        amountOut = swapRouter.exactInputSingle(params);
    }
}
