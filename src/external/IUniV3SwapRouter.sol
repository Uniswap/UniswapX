// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.19;

interface IUniV3SwapRouter {
    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut);
}
