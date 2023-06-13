// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {BaseReactor} from "./BaseReactor.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {ExclusivityOverrideLib} from "../lib/ExclusivityOverrideLib.sol";
import {Permit2Lib} from "../lib/Permit2Lib.sol";
import {DutchDecayLib} from "../lib/DutchDecayLib.sol";
import {ExclusiveDutchOrderLib, ExclusiveDutchOrder, DutchOutput, DutchInput} from "../lib/ExclusiveDutchOrderLib.sol";
import {SignedOrder, ResolvedOrder, InputToken, OrderInfo, OutputToken} from "../base/ReactorStructs.sol";

/// @notice Reactor for exclusive dutch orders
contract ExclusiveDutchOrderReactor is BaseReactor {
    using Permit2Lib for ResolvedOrder;
    using ExclusiveDutchOrderLib for ExclusiveDutchOrder;
    using DutchDecayLib for DutchOutput[];
    using DutchDecayLib for DutchInput;
    using ExclusivityOverrideLib for ResolvedOrder;

    error DeadlineBeforeEndTime();
    error EndTimeBeforeStartTime();
    error InputAndOutputDecay();

    constructor(address _permit2, address _protocolFeeOwner) BaseReactor(_permit2, _protocolFeeOwner) {}

    /// @inheritdoc BaseReactor
    function resolve(SignedOrder calldata signedOrder)
        internal
        view
        virtual
        override
        returns (ResolvedOrder memory resolvedOrder)
    {
        ExclusiveDutchOrder memory order = abi.decode(signedOrder.order, (ExclusiveDutchOrder));
        _validateOrder(order);

        resolvedOrder = ResolvedOrder({
            info: order.info,
            input: order.input.decay(order.startTime, order.endTime),
            outputs: order.outputs.decay(order.startTime, order.endTime),
            sig: signedOrder.sig,
            hash: order.hash()
        });
        resolvedOrder.handleOverride(order.exclusiveFiller, order.startTime, order.exclusivityOverrideBps);
    }

    /// @inheritdoc BaseReactor
    function transferInputTokens(ResolvedOrder memory order, address to) internal override {
        ISignatureTransfer(permit2).permitWitnessTransferFrom(
            order.toPermit(),
            order.transferDetails(to),
            order.info.swapper,
            order.hash,
            ExclusiveDutchOrderLib.PERMIT2_ORDER_TYPE,
            order.sig
        );
    }

    /// @notice validate the dutch order fields
    /// - deadline must be greater than or equal than endTime
    /// - endTime must be greater than or equal to startTime
    /// - if there's input decay, outputs must not decay
    /// - for input decay, startAmount must < endAmount
    /// @dev Throws if the order is invalid
    function _validateOrder(ExclusiveDutchOrder memory order) internal pure {
        if (order.info.deadline < order.endTime) {
            revert DeadlineBeforeEndTime();
        }

        if (order.endTime < order.startTime) {
            revert EndTimeBeforeStartTime();
        }

        if (order.input.startAmount != order.input.endAmount) {
            unchecked {
                for (uint256 i = 0; i < order.outputs.length; i++) {
                    if (order.outputs[i].startAmount != order.outputs[i].endAmount) {
                        revert InputAndOutputDecay();
                    }
                }
            }
        }
    }
}
