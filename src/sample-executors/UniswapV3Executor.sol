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

    /// @dev Only can handle single output
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

        // SwapRouter has to take out inputToken from executor
        ERC20(inputToken).approve(swapRouter, inputAmount);
        IUniV3SwapRouter(swapRouter).exactOutputSingle(IUniV3SwapRouter.ExactOutputSingleParams(
            inputToken,
            outputs[0].token,
            fee,
            address(this),
            outputs[0].amount,
            inputAmount,
            0
        ));
        // Reactor has to take out outputToken from executor (and send to recipient)
        ERC20(outputs[0].token).approve(msg.sender, outputs[0].amount);
    }
}