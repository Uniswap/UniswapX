pragma solidity ^0.8.0;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {IUniV3SwapRouter} from "../../../src/external/IUniV3SwapRouter.sol";

contract MockSwapRouter {
    uint256 public constant SWAP_RATE_GRANULARITY = 10000;
    uint256 public swapRate = 10000; // start with swap at 1 for 1

    function setSwapRate(uint256 newRate) public {
        swapRate = newRate;
    }

    function exactOutputSingle(IUniV3SwapRouter.ExactOutputSingleParams calldata params) external returns (uint256 amountIn) {
        amountIn = (params.amountOut * swapRate) / SWAP_RATE_GRANULARITY;
        require(amountIn <= params.amountInMaximum, 'Too much requested');
        ERC20(params.tokenIn).transferFrom(msg.sender, address(this), amountIn);
        ERC20(params.tokenOut).transfer(params.recipient, params.amountOut);
    }
}