// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {IReactorCallback} from "../interfaces/IReactorCallback.sol";
import {Output} from "../interfaces/ReactorStructs.sol";

interface ISwapRouter02 {
    struct ExactOutputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountOut;
        uint256 amountInMaximum;
        uint160 sqrtPriceLimitX96;
    }

    function exactOutputSingle(ExactOutputSingleParams calldata params) external payable returns (uint256 amountIn);
}

contract UniswapV3Executor is IReactorCallback {

    address constant SWAPROUTER02 = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;

    function reactorCallback(
        Output[] calldata outputs,
        bytes calldata fillData
    ) external {
        address inputToken;
        uint256 inputAmount;
        uint256 deadline;
        bytes memory routerData;

        (inputToken, inputAmount, deadline, routerData) = abi.decode(
            fillData, (address, uint256, uint256, bytes)
        );
    }
}