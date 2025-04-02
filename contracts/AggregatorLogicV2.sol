// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IDexStrategy.sol";

contract AggregatorLogicV2 is Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    mapping(bytes32 => IDexStrategy) public dexStrategies;
    bytes32[] public dexStrategyKeys;

    event StrategySet(bytes32 indexed dexId, address strategy);

    function initialize() external initializer {
        __Ownable_init(msg.sender);
    }
    
    // A new function that can be called after upgrade
    function initializeV2() external {
        // Any V2-specific initialization can go here
        // No initializer modifier, so we can call this after upgrading
        // No onlyOwner modifier, as it will be called through the proxy during upgrade
    }

    function setStrategy(bytes32 dexId, address strategy) external onlyOwner {
        require(strategy != address(0), "Invalid strategy");
        
        if (address(dexStrategies[dexId]) == address(0)) {
            dexStrategyKeys.push(dexId);
        }
        
        dexStrategies[dexId] = IDexStrategy(strategy);
        emit StrategySet(dexId, strategy);
    }

    function getDexCount() external view returns (uint256) {
        return dexStrategyKeys.length;
    }

    function getDexNames() external view returns (string[] memory) {
        string[] memory names = new string[](dexStrategyKeys.length);
        for (uint256 i = 0; i < dexStrategyKeys.length; i++) {
            names[i] = string(abi.encodePacked(dexStrategyKeys[i]));
        }
        return names;
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

        IERC20(tokenIn).safeIncreaseAllowance(address(dexStrategies[bestDex]), amountIn);
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        actualOut = dexStrategies[bestDex].swap(tokenIn, tokenOut, amountIn, minAmountOut, recipient);
    }
} 