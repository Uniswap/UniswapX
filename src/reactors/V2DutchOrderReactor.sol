// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {BaseReactor} from "./BaseReactor.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {ExclusivityOverrideLib} from "../lib/ExclusivityOverrideLib.sol";
import {Permit2Lib} from "../lib/Permit2Lib.sol";
import {DutchDecayLib} from "../lib/DutchDecayLib.sol";
import {V2DutchOrderLib, V2DutchOrder, V2DutchOrderInner, CosignedV2DutchOrder, DutchOutput, DutchInput} from "../lib/V2DutchOrderLib.sol";
import {SignedOrder, ResolvedOrder} from "../base/ReactorStructs.sol";

/// @notice Reactor for v2 dutch orders
/// @dev V2 orders must be cosigned by the specified cosigner to override timings and starting values
/// @dev resolution behavior:
/// - If cosignature is invalid or not from specified cosigner, revert
/// - If inputOverride is 0, then use inner inputs
/// - If inputOverride is nonzero, then ensure it is less than specified input and replace startAmount
/// - For each DutchOutput:
///   - If override is 0, then use inner output
///   - If override is nonzero, then ensure it is greater than specified output and replace startAmount
contract V2DutchOrderReactor is BaseReactor {
    using Permit2Lib for ResolvedOrder;
    using V2DutchOrderLib for V2DutchOrder;
    using DutchDecayLib for DutchOutput[];
    using DutchDecayLib for DutchInput;
    using ExclusivityOverrideLib for ResolvedOrder;

    /// @notice thrown when an order's deadline is before its end time
    error DeadlineBeforeEndTime();

    /// @notice thrown when an order's end time is before its start time
    error OrderEndTimeBeforeStartTime();

    /// @notice thrown when an order's inputs and outputs both decay
    error InputAndOutputDecay();

    /// @notice thrown when an order's cosignature does not match the expected cosigner
    error InvalidCosignature();

    /// @notice thrown when an order's input override is greater than the specified
    error InvalidInputOverride();

    /// @notice thrown when an order's output override is greater than the specified
    error InvalidOutputOverride();

    constructor(IPermit2 _permit2, address _protocolFeeOwner) BaseReactor(_permit2, _protocolFeeOwner) {}

    /// @inheritdoc BaseReactor
    function resolve(SignedOrder calldata signedOrder)
        internal
        view
        virtual
        override
        returns (ResolvedOrder memory resolvedOrder)
    {
        CosignedV2DutchOrder memory cosignedOrder = abi.decode(signedOrder.order, (CosignedV2DutchOrder));
        _validateOrder(cosignedOrder);
        V2DutchOrder memory order = cosignedOrder.order;
        _updateWithOverrides(order);

        resolvedOrder = ResolvedOrder({
            info: order.inner.info,
            input: order.inner.input.decay(order.decayStartTime, order.decayEndTime),
            outputs: order.inner.outputs.decay(order.decayStartTime, order.decayEndTime),
            sig: signedOrder.sig,
            hash: order.hash()
        });
        resolvedOrder.handleOverride(order.exclusiveFiller, order.decayStartTime, order.exclusivityOverrideBps);
    }

    /// @inheritdoc BaseReactor
    function transferInputTokens(ResolvedOrder memory order, address to) internal override {
        permit2.permitWitnessTransferFrom(
            order.toPermit(),
            order.transferDetails(to),
            order.info.swapper,
            order.hash,
            V2DutchOrderLib.PERMIT2_ORDER_TYPE,
            order.sig
        );
    }

    function _updateWithOverrides(V2DutchOrder memory order) internal pure {
        if (order.inputOverride != 0) order.inner.input.startAmount = order.inputOverride;

        for (uint256 i = 0; i < order.inner.outputs.length; i++) {
            DutchOutput memory output = order.inner.outputs[i];
            uint256 outputOverride = order.outputOverrides[i];
            if (outputOverride != 0) output.startAmount = outputOverride;
        }
    }

    /// @notice validate the dutch order fields
    /// - deadline must be greater than or equal than decayEndTime
    /// - decayEndTime must be greater than or equal to decayStartTime
    /// - if there's input decay, outputs must not decay
    /// @dev Throws if the order is invalid
    function _validateOrder(CosignedV2DutchOrder memory cosigned) internal pure {
        V2DutchOrder memory order = cosigned.order;
        if (order.inner.info.deadline < order.decayEndTime) {
            revert DeadlineBeforeEndTime();
        }

        if (order.decayEndTime < order.decayStartTime) {
            revert OrderEndTimeBeforeStartTime();
        }

        (bytes32 r, bytes32 s) = abi.decode(cosigned.signature, (bytes32, bytes32));
        uint8 v = uint8(cosigned.signature[64]);
        address signer = ecrecover(keccak256(abi.encode(order)), v, r, s);
        if (order.inner.cosigner != signer) {
            revert InvalidCosignature();
        }

        if (order.inputOverride != 0 && order.inputOverride > order.inner.input.startAmount) {
            revert InvalidInputOverride();
        }

        if (order.inner.input.startAmount != order.inner.input.endAmount) {
            unchecked {
                for (uint256 i = 0; i < order.inner.outputs.length; i++) {
                    DutchOutput memory output = order.inner.outputs[i];
                    if (output.startAmount != output.endAmount) {
                        revert InputAndOutputDecay();
                    }

                    uint256 outputOverride = order.outputOverrides[i];
                    if (outputOverride < output.startAmount) {
                        revert InvalidOutputOverride();
                    }
                }
            }
        }
    }
}
