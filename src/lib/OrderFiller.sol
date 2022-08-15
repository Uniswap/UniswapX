// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IPermitPost, Permit} from "permitpost/interfaces/IPermitPost.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {IReactorCallback} from "../interfaces/IReactorCallback.sol";
import {
    OrderFill,
    TokenAmount,
    Output,
    ResolvedOrder
} from "../interfaces/ReactorStructs.sol";

library OrderFiller {
    /// @notice fill an order
    function fill(OrderFill memory orderFill) internal {
        IPermitPost(orderFill.permitPost).saltTransferFrom(
            Permit({
                token: orderFill.order.input.token,
                spender: address(this),
                maxAmount: orderFill.order.input.amount,
                deadline: orderFill.order.info.deadline
            }),
            orderFill.order.info.offerer,
            orderFill.fillContract,
            orderFill.order.input.amount,
            orderFill.orderHash,
            orderFill.sig
        );

        IReactorCallback(orderFill.fillContract).reactorCallback(
            orderFill.order.outputs, orderFill.fillData
        );

        // transfer output tokens to their respective recipients
        for (uint256 i = 0; i < orderFill.order.outputs.length; i++) {
            Output memory output = orderFill.order.outputs[i];
            ERC20(output.token).transferFrom(
                orderFill.fillContract, output.recipient, output.amount
            );
        }
    }
}
