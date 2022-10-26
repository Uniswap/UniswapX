// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {BaseReactor} from "./BaseReactor.sol";
import {Permit2Lib} from "../lib/Permit2Lib.sol";
import {OrderHash} from "../lib/OrderHash.sol";
import {SignedOrder, ResolvedOrder, OrderInfo, InputToken, OutputToken} from "../base/ReactorStructs.sol";

/// @dev External struct used to specify simple limit orders
struct LimitOrder {
    // generic order information
    OrderInfo info;
    // The tokens that the offerer will provide when settling the order
    InputToken input;
    // The tokens that must be received to satisfy the order
    OutputToken[] outputs;
}

/// @notice Reactor for simple limit orders
contract LimitOrderReactor is BaseReactor {
    using Permit2Lib for ResolvedOrder;
    using OrderHash for OrderInfo;
    using OrderHash for InputToken;
    using OrderHash for OutputToken[];

    constructor(address _permit2) BaseReactor(_permit2) {}

    string private constant ORDER_TYPE_NAME = "LimitOrder";
    bytes private constant ORDER_TYPE = abi.encodePacked(
        "LimitOrder(OrderInfo info,InputToken input,OutputToken[] outputs)",
        OrderHash.INPUT_TOKEN_TYPE,
        OrderHash.ORDER_INFO_TYPE,
        OrderHash.OUTPUT_TOKEN_TYPE
    );
    bytes32 private constant ORDER_TYPE_HASH = keccak256(ORDER_TYPE);

    /// @inheritdoc BaseReactor
    function resolve(SignedOrder memory signedOrder)
        internal
        pure
        override
        returns (ResolvedOrder memory resolvedOrder)
    {
        LimitOrder memory limitOrder = abi.decode(signedOrder.order, (LimitOrder));
        resolvedOrder = ResolvedOrder({
            info: limitOrder.info,
            input: limitOrder.input,
            outputs: limitOrder.outputs,
            sig: signedOrder.sig,
            hash: _hash(limitOrder)
        });
    }

    /// @inheritdoc BaseReactor
    function transferInputTokens(ResolvedOrder memory order, address to) internal override {
        permit2.permitWitnessTransferFrom(
            order.toPermit(),
            order.info.offerer,
            to,
            order.input.amount,
            order.hash,
            ORDER_TYPE_NAME,
            string(ORDER_TYPE),
            order.sig
        );
    }

    /// @notice hash the given order
    /// @param order the order to hash
    /// @return the eip-712 order hash
    function _hash(LimitOrder memory order) internal pure returns (bytes32) {
        return keccak256(abi.encode(ORDER_TYPE_HASH, order.info.hash(), order.input.hash(), order.outputs.hash()));
    }
}
