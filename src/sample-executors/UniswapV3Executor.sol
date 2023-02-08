// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {WETH} from "solmate/src/tokens/WETH.sol";
import {Owned} from "solmate/src/auth/Owned.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IReactorCallback} from "../interfaces/IReactorCallback.sol";
import {ResolvedOrder} from "../base/ReactorStructs.sol";
import {IUniV3SwapRouter} from "../external/IUniV3SwapRouter.sol";

struct ClaimToken {
    ERC20 token;
    uint256 minOutput;
    bytes path;
}

contract UniswapV3Executor is IReactorCallback, Owned {
    error TransferFailed();

    using SafeTransferLib for ERC20;

    address private immutable swapRouter;
    WETH private immutable weth;

    constructor(address _weth, address _swapRouter, address _owner) Owned(_owner) {
        weth = WETH(payable(_weth));
        swapRouter = _swapRouter;
    }

    /// @dev Can handle multiple resolvedOrders, but the input tokens and output tokens must be the same.
    function reactorCallback(
        ResolvedOrder[] calldata resolvedOrders,
        address, //filler
        bytes calldata path
    ) external {
        // assume for now only single input / output token
        address inputToken = resolvedOrders[0].input.token;
        uint256 inputTokenBalance = ERC20(inputToken).balanceOf(address(this));
        address outputToken = resolvedOrders[0].outputs[0].token;

        // SwapRouter has to take out inputToken from executor
        if (ERC20(inputToken).allowance(address(this), swapRouter) < inputTokenBalance) {
            ERC20(inputToken).approve(swapRouter, type(uint256).max);
        }
        uint256 amountOut = IUniV3SwapRouter(swapRouter).exactInput(
            IUniV3SwapRouter.ExactInputParams({
                path: path,
                recipient: address(this),
                amountIn: inputTokenBalance,
                amountOutMinimum: 0
            })
        );
        // Reactor has to take out outputToken from executor (and send to recipient)
        if (ERC20(outputToken).allowance(address(this), msg.sender) < amountOut) {
            ERC20(outputToken).approve(msg.sender, type(uint256).max);
        }
    }

    /// @notice tranfer any earned tokens to the owner
    function claimFees(address to, ClaimToken[] calldata claims) external onlyOwner {
        for (uint256 i = 0; i < claims.length; i++) {
            ClaimToken calldata claim = claims[i];

            uint256 balance = claim.token.balanceOf(address(this));
            if (claim.token.allowance(address(this), swapRouter) < balance) {
                claim.token.approve(swapRouter, type(uint256).max);
            }

            IUniV3SwapRouter(swapRouter).exactInput(
                IUniV3SwapRouter.ExactInputParams({
                    path: claim.path,
                    recipient: address(this),
                    amountIn: balance,
                    amountOutMinimum: claim.minOutput
                })
            );
        }

        // assumption is that the claims swap to WETH
        uint256 amount = weth.balanceOf(address(this));
        weth.withdraw(amount);

        (bool success,) = to.call{value: amount}("");
        if (!success) {
            revert TransferFailed();
        }
    }

    receive() external payable {}
}
