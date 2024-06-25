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

    error InvalidDeadline();
    error OrderNotFillable();

    constructor(IPermit2 _permit2, address _protocolFeeOwner) BaseReactor(_permit2, _protocolFeeOwner) {}

    /// @inheritdoc BaseReactor
    function _resolve(SignedOrder calldata signedOrder)
        internal
        view
        override
        returns (ResolvedOrder memory resolvedOrder)
    {
        PriorityOrder memory priorityOrder = abi.decode(signedOrder.order, (PriorityOrder));
        _validateOrder(priorityOrder);
        
        uint256 priorityFee = tx.gasprice - block.basefee;
        resolvedOrder = ResolvedOrder({
            info: priorityOrder.info,
            input: priorityOrder.input.scale(priorityFee),
            outputs: priorityOrder.outputs.scale(priorityFee),
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

    /// @notice validate the priority order fields
    /// - deadline must be in the future
    /// - startBlock must be in the past
    /// - if input scales with priority fee, outputs must not scale
    /// @dev Throws if the order is invalid
    function _validateOrder(PriorityOrder memory order) internal view {
        if (order.info.deadline < block.timestamp) {
            revert InvalidDeadline();
        }

        if (order.startBlock > block.number) {
            revert OrderNotFillable();
        }

        if(order.input.bpsPerPriorityFeeWei > 0) {
            for(uint256 i = 0; i < order.outputs.length; i++) {
                if(order.outputs[i].bpsPerPriorityFeeWei > 0) {
                    revert OrderNotFillable();
                }
            }
        }
    }
}
