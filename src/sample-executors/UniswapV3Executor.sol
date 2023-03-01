// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {Owned} from "solmate/src/auth/Owned.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IReactorCallback} from "../interfaces/IReactorCallback.sol";
import {IReactor} from "../interfaces/IReactor.sol";
import {ResolvedOrder, SignedOrder} from "../base/ReactorStructs.sol";
import {IUniV3SwapRouter} from "../external/IUniV3SwapRouter.sol";

contract UniswapV3Executor is IReactorCallback, Owned {
    using SafeTransferLib for ERC20;

    error FillerNotOwner();
    error CallerNotReactor();

    address public immutable swapRouter;
    address public immutable reactor;

    constructor(address _reactor, address _swapRouter, address _owner) Owned(_owner) {
        reactor = _reactor;
        swapRouter = _swapRouter;
    }

    function execute(SignedOrder calldata order, bytes calldata fillData) external {
        require(msg.sender == owner, "UNAUTHORIZED");
        IReactor(reactor).execute(order, fillData);
    }

    function executeBatch(SignedOrder[] calldata order, bytes calldata fillData) external {
        require(msg.sender == owner, "UNAUTHORIZED");
        IReactor(reactor).executeBatch(order, fillData);
    }

    /// @dev Can handle multiple resolvedOrders, but the input tokens and output tokens must be the same.
    function reactorCallback(ResolvedOrder[] calldata resolvedOrders, bytes calldata path) external {

        if (msg.sender != reactor) {
            revert CallerNotReactor();
        }

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
    function claimTokens(ERC20 token) external onlyOwner {
        token.safeTransfer(owner, token.balanceOf(address(this)));
    }
}
