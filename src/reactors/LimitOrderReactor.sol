// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {BaseReactor} from "./BaseReactor.sol";
import {Permit2Lib} from "../lib/Permit2Lib.sol";
import {LimitOrderLib, LimitOrder} from "../lib/LimitOrderLib.sol";
import {SignedOrder, ResolvedOrder, OrderInfo, InputToken, OutputToken} from "../base/ReactorStructs.sol";

/// @notice Reactor for simple limit orders
contract LimitOrderReactor is BaseReactor {
    using Permit2Lib for ResolvedOrder;
    using LimitOrderLib for LimitOrder;

    constructor(address _permit2) BaseReactor(_permit2) {}

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
            hash: limitOrder.hash()
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
            LimitOrderLib.ORDER_TYPE_NAME,
            string(LimitOrderLib.ORDER_TYPE),
            order.sig
        );
    }
}
