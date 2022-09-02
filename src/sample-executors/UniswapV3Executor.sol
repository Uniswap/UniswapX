// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {IReactorCallback} from "../interfaces/IReactorCallback.sol";
import {Output, ResolvedOrder} from "../lib/ReactorStructs.sol";
import {IUniV3SwapRouter} from "../external/IUniV3SwapRouter.sol";

contract UniswapV3Executor is IReactorCallback {
    address public immutable swapRouter;

    constructor(address _swapRouter) {
        swapRouter = _swapRouter;
    }

    /// @dev Only can handle 1 resolvedOrder. outputs must be of the same token.
    function reactorCallback(ResolvedOrder[] calldata resolvedOrders, bytes calldata fillData) external {
        require(resolvedOrders.length == 1, "resolvedOrders.length !=1");
        ResolvedOrder memory resolvedOrder = resolvedOrders[0];

        uint24 fee = abi.decode(fillData, (uint24));
        uint256 totalOutputAmount;
        for (uint256 i = 0; i < resolvedOrder.outputs.length; i++) {
            totalOutputAmount += resolvedOrder.outputs[i].amount;
        }

        // SwapRouter has to take out inputToken from executor
        if (ERC20(resolvedOrder.input.token).allowance(address(this), swapRouter) < resolvedOrder.input.amount) {
            ERC20(resolvedOrder.input.token).approve(swapRouter, resolvedOrder.input.amount);
        }
        IUniV3SwapRouter(swapRouter).exactOutputSingle(
            IUniV3SwapRouter.ExactOutputSingleParams(
                resolvedOrder.input.token,
                resolvedOrder.outputs[0].token,
                fee,
                address(this),
                totalOutputAmount,
                resolvedOrder.input.amount,
                0
            )
        );
        // Reactor has to take out outputToken from executor (and send to recipient)
        if (ERC20(resolvedOrder.outputs[0].token).allowance(address(this), msg.sender) < totalOutputAmount) {
            ERC20(resolvedOrder.outputs[0].token).approve(msg.sender, totalOutputAmount);
        }
    }
}
