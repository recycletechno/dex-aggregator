// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../interfaces/IDexStrategy.sol";
import "../interfaces/IUniswapV2Router02.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract DexStrategyUniV2 is IDexStrategy {
    using SafeERC20 for IERC20;

    IUniswapV2Router02 public immutable router;

    constructor(address _router) {
        require(_router != address(0), "Invalid router");
        router = IUniswapV2Router02(_router);
    }

    function getQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view virtual override returns (uint256 amountOut) {
        if (amountIn == 0 || tokenIn == tokenOut) {
            return 0;
        }

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        // If the pair doesn't exist, the call reverts. We can do a try/catch or just let it revert.
        try router.getAmountsOut(amountIn, path) returns (uint256[] memory amounts) {
            amountOut = amounts[1];
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

        // First approve the router to spend tokenIn
        IERC20(tokenIn).safeIncreaseAllowance(address(router), amountIn);

        // Then transfer tokens from caller to this contract
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        uint256[] memory amounts = router.swapExactTokensForTokens(
            amountIn,
            minAmountOut,
            path,
            recipient,
            block.timestamp + 120
        );

        amountOut = amounts[1];
    }
}
