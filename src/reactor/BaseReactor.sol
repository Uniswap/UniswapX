// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IPermitPost, Permit} from "permitpost/interfaces/IPermitPost.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {OrderValidator} from "../lib/OrderValidator.sol";
import {ReactorEvents} from "../lib/ReactorEvents.sol";
import {IReactorCallback} from "../interfaces/IReactorCallback.sol";
import {ResolvedOrder, OrderInfo, OrderStatus, TokenAmount, Signature, Output} from "../lib/ReactorStructs.sol";

/// @notice Reactor for simple limit orders
contract BaseReactor is OrderValidator, ReactorEvents {
    address public immutable permitPost;

    constructor(address _permitPost) {
        permitPost = _permitPost;
    }

    /// @notice validates and fills an order, marking it as filled
    function _fill(
        ResolvedOrder memory order,
        Signature calldata sig,
        bytes32 orderHash,
        address fillContract,
        bytes calldata fillData
    )
        internal
    {
        _validate(order.info);
        _updateFilled(orderHash);
        IPermitPost(permitPost).saltTransferFrom(
            Permit({token: order.input.token, spender: address(this), maxAmount: order.input.amount, deadline: order.info.deadline}),
            order.info.offerer,
            fillContract,
            order.input.amount,
            orderHash,
            sig
        );

        ResolvedOrder[] memory resolvedOrders = new ResolvedOrder[](1);
        resolvedOrders[0] = order;
        IReactorCallback(fillContract).reactorCallback(resolvedOrders, fillData);

        // transfer output tokens to their respective recipients
        for (uint256 i = 0; i < order.outputs.length; i++) {
            Output memory output = order.outputs[i];
            ERC20(output.token).transferFrom(fillContract, output.recipient, output.amount);
        }

        emit Fill(orderHash, msg.sender);
    }
}
