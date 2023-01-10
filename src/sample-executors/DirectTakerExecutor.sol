// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {Owned} from "solmate/src/auth/Owned.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IReactorCallback} from "../interfaces/IReactorCallback.sol";
import {OutputToken, ResolvedOrder} from "../base/ReactorStructs.sol";

contract DirectTakerExecutor is IReactorCallback, Owned {
    using SafeTransferLib for ERC20;

    constructor(address _owner) Owned(_owner) {}

    function reactorCallback(ResolvedOrder[] calldata resolvedOrders, address taker, bytes calldata) external {
        // Only handle 1 resolved order
        require(resolvedOrders.length == 1, "resolvedOrders.length != 1");

        uint256 totalOutputAmount;
        // transfer output tokens from taker to this
        for (uint256 i = 0; i < resolvedOrders[0].outputs.length; i++) {
            OutputToken memory output = resolvedOrders[0].outputs[i];
            ERC20(output.token).safeTransferFrom(taker, address(this), output.amount);
            totalOutputAmount += output.amount;
        }
        // Assumed that all outputs are of the same token
        ERC20(resolvedOrders[0].outputs[0].token).approve(msg.sender, totalOutputAmount);
        // transfer input tokens from this to taker
        ERC20(resolvedOrders[0].input.token).safeTransfer(taker, resolvedOrders[0].input.amount);
    }
}
