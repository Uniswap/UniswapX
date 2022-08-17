// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface IUniV3SwapRouter {
    struct ExactOutputSingleParams {
        address tokenIn; // from fillData
        address tokenOut; // from <outputs>
        uint24 fee; // from fillData
        address recipient; // fillContract (this)
        uint256 amountOut; // from <outputs>
        uint256 amountInMaximum; // from fillData
        uint160 sqrtPriceLimitX96; // 0
    }

    function exactOutputSingle(ExactOutputSingleParams calldata params) external payable returns (uint256 amountIn);
}