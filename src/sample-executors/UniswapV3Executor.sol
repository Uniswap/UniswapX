// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {IReactorCallback} from "../interfaces/IReactorCallback.sol";
import {Output} from "../interfaces/ReactorStructs.sol";

interface ISwapRouter02 {
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

contract UniswapV3Executor is IReactorCallback {

    address constant SWAPROUTER02 = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;

    function reactorCallback(
        Output[] calldata outputs,
        bytes calldata fillData
    ) external {
        address inputToken;
        uint24 fee;
        uint256 inputAmount;

        (inputToken, fee, inputAmount) = abi.decode(
            fillData, (address, uint24, uint256)
        );

        ISwapRouter02(SWAPROUTER02).exactOutputSingle(ISwapRouter02.ExactOutputSingleParams(
            inputToken,
            outputs[0].token,
            fee,
            address(this),
            outputs[0].amount,
            inputAmount,
            0
        ));
    }
}