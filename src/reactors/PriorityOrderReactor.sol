// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {BaseReactor} from "./BaseReactor.sol";
import {Permit2Lib} from "../lib/Permit2Lib.sol";
import {PriorityOrderLib, PriorityOrder, PriorityInput, PriorityOutput} from "../lib/PriorityOrderLib.sol";
import {PriorityFeeLib} from "../lib/PriorityFeeLib.sol";
import {SignedOrder, ResolvedOrder} from "../base/ReactorStructs.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";

/// @notice Reactor for simple limit orders
contract PriorityOrderReactor is BaseReactor {
    using Permit2Lib for ResolvedOrder;
    using PriorityOrderLib for PriorityOrder;
    using PriorityFeeLib for PriorityInput;
    using PriorityFeeLib for PriorityOutput[];

    constructor(IPermit2 _permit2, address _protocolFeeOwner) BaseReactor(_permit2, _protocolFeeOwner) {}

    /// @inheritdoc BaseReactor
    function _resolve(SignedOrder calldata signedOrder)
        internal
        view
        override
        returns (ResolvedOrder memory resolvedOrder)
    {
        PriorityOrder memory priorityOrder = abi.decode(signedOrder.order, (PriorityOrder));
        uint256 priorityFee = tx.gasprice - block.basefee;
        resolvedOrder = ResolvedOrder({
            info: priorityOrder.info,
            input: priorityOrder.input.scale(priorityOrder.bpsPerPriorityFeeWei, priorityFee),
            outputs: priorityOrder.outputs.scale(priorityOrder.bpsPerPriorityFeeWei, priorityFee),
            sig: signedOrder.sig,
            hash: priorityOrder.hash()
        });
    }

    /// @inheritdoc BaseReactor
    function _transferInputTokens(ResolvedOrder memory order, address to) internal override {
        permit2.permitWitnessTransferFrom(
            order.toPermit(),
            order.transferDetails(to),
            order.info.swapper,
            order.hash,
            PriorityOrderLib.PERMIT2_ORDER_TYPE,
            order.sig
        );
    }
}
