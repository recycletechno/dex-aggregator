// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IDexStrategy.sol";

/**
 * @title AggregatorLogic
 * @dev Upgradeable aggregator logic. Replaces the constructor with an `initialize()` function.
 */
contract AggregatorLogic is Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    mapping(bytes32 => IDexStrategy) public dexStrategies;
    bytes32[] public dexStrategyKeys;

    event StrategySet(bytes32 indexed dexId, address strategy);

    /**
     * @notice Instead of a constructor, we use `initialize()`. 
     *         This will be called exactly once by the proxy after deployment.
     */
    function initialize() external initializer {
        __Ownable_init(msg.sender);
    }

    function setStrategy(bytes32 dexId, address strategy) external onlyOwner {
        require(strategy != address(0), "Invalid strategy");
        
        // If the strategy doesn't exist yet, add the key to the array
        if (address(dexStrategies[dexId]) == address(0)) {
            dexStrategyKeys.push(dexId);
        }
        
        dexStrategies[dexId] = IDexStrategy(strategy);
        emit StrategySet(dexId, strategy);
    }

    function getDexCount() external view returns (uint256) {
        return dexStrategyKeys.length;
    }

    function getBestQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) public returns (bytes32 bestDex, uint256 bestAmountOut) {
        bestDex = "";
        bestAmountOut = 0;

        for (uint256 i = 0; i < dexStrategyKeys.length; i++) {
            bytes32 dexId = dexStrategyKeys[i];
            IDexStrategy strategy = dexStrategies[dexId];
            if (address(strategy) == address(0)) continue;
            
            uint256 quote = strategy.getQuote(tokenIn, tokenOut, amountIn);
            if (quote > bestAmountOut) {
                bestDex = dexId;
                bestAmountOut = quote;
            }
        }
    }

    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient
    ) external returns (uint256 actualOut) {
        (bytes32 bestDex, uint256 bestQuote) = getBestQuote(tokenIn, tokenOut, amountIn);
        require(bestDex != "", "No DEX available");
        require(bestQuote >= minAmountOut, "Slippage too high");

        // First approve the strategy to spend tokens
        IERC20(tokenIn).safeIncreaseAllowance(address(dexStrategies[bestDex]), amountIn);

        // Then transfer tokens from caller to this contract
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // Execute the swap
        actualOut = dexStrategies[bestDex].swap(tokenIn, tokenOut, amountIn, minAmountOut, recipient);
    }
}
