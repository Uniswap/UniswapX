// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {IReactorCallback} from "../interfaces/IReactorCallback.sol";
import {Output, ResolvedOrder} from "../interfaces/ReactorStructs.sol";
import {IUniV3SwapRouter} from "../external/IUniV3SwapRouter.sol";

contract UniswapV3Executor is IReactorCallback {

    address public immutable swapRouter;

    constructor(address _swapRouter) {
        swapRouter = _swapRouter;
    }

    /// @dev Only can handle 1 resolvedOrder. outputs must be of the same token.
    function reactorCallback(
        ResolvedOrder[] calldata resolvedOrders,
        bytes calldata fillData
    ) external {
        require(resolvedOrders.length == 1, "resolvedOrders.length !=1");
        ResolvedOrder memory resolvedOrder = resolvedOrders[0];

        (uint24 fee, address reactor) = abi.decode(fillData, (uint24, address));
        uint256 totalOutputAmount;
        for (uint i = 0; i < resolvedOrder.outputs.length; i++) {
            totalOutputAmount += resolvedOrder.outputs[i].amount;
        }

        // SwapRouter has to take out inputToken from executor
        ERC20(resolvedOrder.input.token).approve(swapRouter, resolvedOrder.input.amount);
        IUniV3SwapRouter(swapRouter).exactOutputSingle(IUniV3SwapRouter.ExactOutputSingleParams(
            resolvedOrder.input.token,
            resolvedOrder.outputs[0].token,
            fee,
            address(this),
            totalOutputAmount,
            resolvedOrder.input.amount,
            0
        ));
        // Reactor has to take out outputToken from executor (and send to recipient)
        ERC20(resolvedOrder.outputs[0].token).approve(reactor, totalOutputAmount);
    }
}