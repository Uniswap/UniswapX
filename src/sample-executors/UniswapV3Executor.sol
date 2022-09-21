// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {IReactorCallback} from "../interfaces/IReactorCallback.sol";
import {ResolvedOrder} from "../base/ReactorStructs.sol";
import {IUniV3SwapRouter} from "../external/IUniV3SwapRouter.sol";

contract UniswapV3Executor is IReactorCallback {
    address public immutable swapRouter;

    constructor(address _swapRouter) {
        swapRouter = _swapRouter;
    }

    /// @dev Can handle multiple resolvedOrders, but the input tokens and output tokens must be the same.
    function reactorCallback(ResolvedOrder[] calldata resolvedOrders, bytes calldata fillData) external {
        uint24 fee = abi.decode(fillData, (uint24));
        address inputToken = resolvedOrders[0].input.token;
        uint256 inputTokenBalance = ERC20(inputToken).balanceOf(address(this));
        address outputToken = resolvedOrders[0].outputs[0].token;

        // SwapRouter has to take out inputToken from executor
        if (ERC20(inputToken).allowance(address(this), swapRouter) < inputTokenBalance) {
            ERC20(inputToken).approve(swapRouter, inputTokenBalance);
        }
        uint256 amountOut = IUniV3SwapRouter(swapRouter).exactInputSingle(
            IUniV3SwapRouter.ExactInputSingleParams(
                inputToken, outputToken, fee, address(this), inputTokenBalance, 0, 0
            )
        );
        // Reactor has to take out outputToken from executor (and send to recipient)
        if (ERC20(outputToken).allowance(address(this), msg.sender) < amountOut) {
            ERC20(outputToken).approve(msg.sender, amountOut);
        }
    }
}
