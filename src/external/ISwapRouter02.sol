// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

struct ExactInputSingleParams {
    address tokenIn;
    address tokenOut;
    uint24 fee;
    address recipient;
    uint256 amountIn;
    uint256 amountOutMinimum;
    uint160 sqrtPriceLimitX96;
}

interface ISwapRouter02 {
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
    function multicall(uint256 deadline, bytes[] calldata data) external payable returns (bytes[] memory results);
    function swapExactTokensForTokens(uint256 amountIn, uint256 amountOutMin, address[] calldata path, address to)
        external
        payable
        returns (uint256 amountOut);
    function unwrapWETH9(uint256 amountMinimum) external payable;
    function WETH9() external view returns (address);
}
