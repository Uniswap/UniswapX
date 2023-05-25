// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.19;

import {BaseReactor} from "./BaseReactor.sol";
import {Permit2Lib} from "../lib/Permit2Lib.sol";
import {LimitOrderLib, LimitOrder} from "../lib/LimitOrderLib.sol";
import {SignedOrder, ResolvedOrder, OrderInfo, InputToken, OutputToken} from "../base/ReactorStructs.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";

/// @notice Reactor for simple limit orders
contract LimitOrderReactor is BaseReactor {
    using Permit2Lib for ResolvedOrder;
    using LimitOrderLib for LimitOrder;

    constructor(address _permit2, address _protocolFeeOwner) BaseReactor(_permit2, _protocolFeeOwner) {}

    /// @inheritdoc BaseReactor
    function resolve(SignedOrder calldata signedOrder)
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
        ISignatureTransfer(permit2).permitWitnessTransferFrom(
            order.toPermit(),
            order.transferDetails(to),
            order.info.swapper,
            order.hash,
            LimitOrderLib.PERMIT2_ORDER_TYPE,
            order.sig
        );
    }
}
