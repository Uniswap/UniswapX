pragma solidity ^0.8.16;

import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {Path} from "../lib/Path.sol";
import {IUniV3SwapRouter} from "../../../src/external/IUniV3SwapRouter.sol";

contract MockSwapRouter {
    using SafeTransferLib for ERC20;
    using Path for bytes;

    uint256 public constant SWAP_RATE_GRANULARITY = 10000;
    uint256 public swapRate = 10000; // start with swap at 1 for 1

    function setSwapRate(uint256 newRate) public {
        swapRate = newRate;
    }

    function exactInput(IUniV3SwapRouter.ExactInputParams calldata params) external returns (uint256 amountOut) {
        bytes memory path = params.path;
        (address tokenIn,,) = path.decodeFirstPool();

        while (path.hasMultiplePools()) {
            path = path.skipToken();
        }
        (, address tokenOut,) = path.decodeFirstPool();

        amountOut = (params.amountIn * swapRate) / SWAP_RATE_GRANULARITY;
        require(amountOut >= params.amountOutMinimum, "Too little received");
        ERC20(tokenIn).safeTransferFrom(msg.sender, address(this), params.amountIn);
        ERC20(tokenOut).safeTransfer(params.recipient, amountOut);
    }
}
