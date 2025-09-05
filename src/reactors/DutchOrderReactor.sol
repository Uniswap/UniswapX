// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {BaseReactor} from "./BaseReactor.sol";
import {Permit2Lib} from "../lib/Permit2Lib.sol";
import {DutchDecayLib} from "../lib/DutchDecayLib.sol";
import {DutchOrderLib, DutchOrder, DutchOutput, DutchInput} from "../lib/DutchOrderLib.sol";
import {SignedOrder, ResolvedOrder} from "../base/ReactorStructs.sol";

/// @notice Reactor for dutch orders
contract DutchOrderReactor is BaseReactor {
    using Permit2Lib for ResolvedOrder;
    using DutchOrderLib for DutchOrder;
    using DutchDecayLib for DutchOutput[];
    using DutchDecayLib for DutchInput;

    /// @notice thrown when an order's deadline is before its end time
    error DeadlineBeforeEndTime();

    /// @notice thrown when an order's inputs and outputs both decay
    error InputAndOutputDecay();

    constructor(IPermit2 _permit2, address _protocolFeeOwner) BaseReactor(_permit2, _protocolFeeOwner) {}

    /// @inheritdoc BaseReactor
    function _resolve(SignedOrder calldata signedOrder)
        internal
        view
        virtual
        override
        returns (ResolvedOrder memory resolvedOrder)
    {
        DutchOrder memory order = abi.decode(signedOrder.order, (DutchOrder));
        _validateOrder(order);

        resolvedOrder = ResolvedOrder({
            info: order.info,
            input: order.input.decay(order.decayStartTime, order.decayEndTime),
            outputs: order.outputs.decay(order.decayStartTime, order.decayEndTime),
            sig: signedOrder.sig,
            hash: order.hash()
        });
    }

    /// @inheritdoc BaseReactor
    function _transferInputTokens(ResolvedOrder memory order, address to) internal override {
        permit2.permitWitnessTransferFrom(
            order.toPermit(),
            order.transferDetails(to),
            order.info.swapper,
            order.hash,
            DutchOrderLib.PERMIT2_ORDER_TYPE,
            order.sig
        );
    }

    /// @notice validate the dutch order fields
    /// - deadline must be greater than or equal than decayEndTime
    /// - if there's input decay, outputs must not decay
    /// @dev Throws if the order is invalid
    function _validateOrder(DutchOrder memory order) internal pure {
        if (order.info.deadline < order.decayEndTime) {
            revert DeadlineBeforeEndTime();
        }

        if (order.input.startAmount != order.input.endAmount) {
            for (uint256 i = 0; i < order.outputs.length; i++) {
                if (order.outputs[i].startAmount != order.outputs[i].endAmount) {
                    revert InputAndOutputDecay();
                }
            }
        }
    }
}
