// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {Owned} from "solmate/src/auth/Owned.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IReactorCallback} from "../interfaces/IReactorCallback.sol";
import {ResolvedOrder} from "../base/ReactorStructs.sol";
import {CurrencyLibrary} from "../lib/CurrencyLibrary.sol";
import {IUniV3SwapRouter} from "../external/IUniV3SwapRouter.sol";

contract UniswapV3Executor is IReactorCallback, Owned {
    using CurrencyLibrary for address;
    using SafeTransferLib for ERC20;

    error FillerNotOwner();
    error CallerNotReactor();

    address public immutable swapRouter;
    address public immutable reactor;

    constructor(address _reactor, address _swapRouter, address _owner) Owned(_owner) {
        reactor = _reactor;
        swapRouter = _swapRouter;
    }

    /// @dev Can handle multiple resolvedOrders, but the input tokens and output tokens must be the same.
    function reactorCallback(ResolvedOrder[] calldata resolvedOrders, address filler, bytes calldata path) external {
        if (filler != owner) {
            revert FillerNotOwner();
        }
        if (msg.sender != reactor) {
            revert CallerNotReactor();
        }

        // assume for now only single input / output token
        address inputToken = resolvedOrders[0].input.token;
        uint256 inputTokenBalance = ERC20(inputToken).balanceOf(address(this));
        address outputToken = resolvedOrders[0].outputs[0].token;

        // SwapRouter has to take out inputToken from executor
        if (ERC20(inputToken).allowance(address(this), swapRouter) < inputTokenBalance) {
            ERC20(inputToken).safeApprove(swapRouter, type(uint256).max);
        }
        IUniV3SwapRouter(swapRouter).exactInput(
            IUniV3SwapRouter.ExactInputParams({
                path: path,
                recipient: address(this),
                amountIn: inputTokenBalance,
                amountOutMinimum: 0
            })
        );

        for (uint256 i = 0; i < resolvedOrders.length; i++) {
            ResolvedOrder memory order = resolvedOrders[i];
            for (uint256 j = 0; j < order.outputs.length; j++) {
                outputToken.transfer(order.outputs[j].recipient, order.outputs[j].amount);
            }
        }
    }

    /// @notice tranfer any earned tokens to the owner
    function claimTokens(ERC20 token) external onlyOwner {
        token.safeTransfer(owner, token.balanceOf(address(this)));
    }
}
