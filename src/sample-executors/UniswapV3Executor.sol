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

    /// @dev Only can handle single output
    function reactorCallback(
        ResolvedOrder[] calldata resolvedOrders,
        bytes calldata fillData
    ) external {
        require(resolvedOrders.length == 1, "resolvedOrders.length !=1");

        (address inputToken, uint24 fee, uint256 inputAmount, address reactor) = abi.decode(
            fillData, (address, uint24, uint256, address)
        );

        // SwapRouter has to take out inputToken from executor
        ERC20(inputToken).approve(swapRouter, inputAmount);
        IUniV3SwapRouter(swapRouter).exactOutputSingle(IUniV3SwapRouter.ExactOutputSingleParams(
            inputToken,
            resolvedOrders[0].outputs[0].token,
            fee,
            address(this),
            resolvedOrders[0].outputs[0].amount,
            inputAmount,
            0
        ));
        // Reactor has to take out outputToken from executor (and send to recipient)
        ERC20(resolvedOrders[0].outputs[0].token).approve(reactor, resolvedOrders[0].outputs[0].amount);
    }
}