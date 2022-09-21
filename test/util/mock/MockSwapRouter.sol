pragma solidity ^0.8.16;

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {IUniV3SwapRouter} from "../../../src/external/IUniV3SwapRouter.sol";

contract MockSwapRouter {
    using SafeTransferLib for ERC20;

    uint256 public constant SWAP_RATE_GRANULARITY = 10000;
    uint256 public swapRate = 10000; // start with swap at 1 for 1

    function setSwapRate(uint256 newRate) public {
        swapRate = newRate;
    }

    function exactOutputSingle(IUniV3SwapRouter.ExactOutputSingleParams calldata params)
        external
        returns (uint256 amountIn)
    {
        amountIn = (params.amountOut * swapRate) / SWAP_RATE_GRANULARITY;
        require(amountIn <= params.amountInMaximum, "Too much requested");
        ERC20(params.tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        ERC20(params.tokenOut).safeTransfer(params.recipient, params.amountOut);
    }

    function exactInputSingle(IUniV3SwapRouter.ExactInputSingleParams calldata params)
        external
        returns (uint256 amountOut)
    {
        amountOut = (params.amountIn * swapRate) / SWAP_RATE_GRANULARITY;
        require(amountOut >= params.amountOutMinimum, "Too little received");
        ERC20(params.tokenIn).safeTransferFrom(msg.sender, address(this), params.amountIn);
        ERC20(params.tokenOut).safeTransfer(params.recipient, amountOut);
    }
}
