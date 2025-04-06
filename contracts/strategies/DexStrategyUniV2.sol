// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../interfaces/IDexStrategy.sol";
import "../interfaces/IUniswapV2Router02.sol";
import "../interfaces/IUniswapV2Factory.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract DexStrategyUniV2 is IDexStrategy {
    using SafeERC20 for IERC20;

    IUniswapV2Router02 public immutable router;
    IUniswapV2Factory public immutable factory;

    constructor(address _router, address _factory) {
        require(_router != address(0), "Invalid router");
        require(_factory != address(0), "Invalid factory");
        router = IUniswapV2Router02(_router);
        factory = IUniswapV2Factory(_factory);
    }

    function isPairSupported(
        address tokenIn,
        address tokenOut
    ) public view override returns (bool) {
        if (tokenIn == tokenOut) return false;
        address pair = factory.getPair(tokenIn, tokenOut);
        return pair != address(0);
    }

    function getQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view virtual override returns (uint256 amountOut) {
        if (amountIn == 0 || tokenIn == tokenOut) {
            return 0;
        }

        if (!isPairSupported(tokenIn, tokenOut)) {
            return 0;
        }

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        uint256[] memory amounts = router.getAmountsOut(amountIn, path);
        amountOut = amounts[1];
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
