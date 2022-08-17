// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {IReactorCallback} from "../interfaces/IReactorCallback.sol";
import {Output} from "../interfaces/ReactorStructs.sol";
import {IUniV3SwapRouter} from "../external/IUniV3SwapRouter.sol";

contract UniswapV3Executor is IReactorCallback {

    address public immutable swapRouter;

    constructor(address _swapRouter) {
        swapRouter = _swapRouter;
    }

    // Only handle 1 output
    function reactorCallback(
        Output[] calldata outputs,
        bytes calldata fillData
    ) external {
        require(outputs.length == 1, "output.length !=1");

        address inputToken;
        uint24 fee;
        uint256 inputAmount;

        (inputToken, fee, inputAmount) = abi.decode(
            fillData, (address, uint24, uint256)
        );

        ERC20(inputToken).approve(swapRouter, outputs[0].amount);
        IUniV3SwapRouter(swapRouter).exactOutputSingle(IUniV3SwapRouter.ExactOutputSingleParams(
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