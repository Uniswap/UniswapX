// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {BaseReactor} from "./BaseReactor.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {Permit2Lib} from "../lib/Permit2Lib.sol";
import {ExclusivityLib} from "../lib/ExclusivityLib.sol";
import {DutchDecayLib} from "../lib/DutchDecayLib.sol";
import {V2DutchOrderLib, V2DutchOrder, CosignerData, DutchOutput, DutchInput} from "../lib/V2DutchOrderLib.sol";
import {SignedOrder, ResolvedOrder} from "../base/ReactorStructs.sol";

/// @notice Reactor for v2 dutch orders
/// @dev V2 orders must be cosigned by the specified cosigner to override timings and starting values
/// @dev resolution behavior:
/// - If cosignature is invalid or not from specified cosigner, revert
/// - If inputAmount is 0, then use baseInput
/// - If inputAmount is nonzero, then ensure it is less than specified baseOutput and replace startAmount
/// - For each outputAmount:
///   - If amount is 0, then use baseOutput
///   - If amount is nonzero, then ensure it is greater than specified baseOutput and replace startAmount
contract V2DutchOrderReactor is BaseReactor {
    using Permit2Lib for ResolvedOrder;
    using V2DutchOrderLib for V2DutchOrder;
    using DutchDecayLib for DutchOutput[];
    using DutchDecayLib for DutchInput;
    using ExclusivityLib for ResolvedOrder;

    /// @notice thrown when an order's deadline is before its end time
    error DeadlineBeforeEndTime();

    /// @notice thrown when an order's inputs and outputs both decay
    error InputAndOutputDecay();

    /// @notice thrown when an order's cosignature does not match the expected cosigner
    error InvalidCosignature();

    /// @notice thrown when an order's cosigner input is greater than the specified
    error InvalidCosignerInput();

    /// @notice thrown when an order's cosigner output is less than the specified
    error InvalidCosignerOutput();

    constructor(IPermit2 _permit2, address _protocolFeeOwner) BaseReactor(_permit2, _protocolFeeOwner) {}

    /// @inheritdoc BaseReactor
    function resolve(SignedOrder calldata signedOrder)
        internal
        view
        virtual
        override
        returns (ResolvedOrder memory resolvedOrder)
    {
        V2DutchOrder memory order = abi.decode(signedOrder.order, (V2DutchOrder));
        // hash the order _before_ overriding amounts, as this is the hash the user would have signed
        bytes32 orderHash = order.hash();

        _validateOrder(orderHash, order);
        _updateWithCosignerAmounts(order);

        resolvedOrder = ResolvedOrder({
            info: order.info,
            input: order.baseInput.decay(order.cosignerData.decayStartTime, order.cosignerData.decayEndTime),
            outputs: order.baseOutputs.decay(order.cosignerData.decayStartTime, order.cosignerData.decayEndTime),
            sig: signedOrder.sig,
            hash: orderHash
        });
        resolvedOrder.handleExclusiveOverride(
            order.cosignerData.exclusiveFiller,
            order.cosignerData.decayStartTime,
            order.cosignerData.exclusivityOverrideBps
        );
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

    function _updateWithCosignerAmounts(V2DutchOrder memory order) internal pure {
        if (order.cosignerData.inputAmount != 0) {
            if (order.cosignerData.inputAmount > order.baseInput.startAmount) {
                revert InvalidCosignerInput();
            }
            order.baseInput.startAmount = order.cosignerData.inputAmount;
        }

        if (order.cosignerData.outputAmounts.length != order.baseOutputs.length) {
            revert InvalidCosignerOutput();
        }
        for (uint256 i = 0; i < order.baseOutputs.length; i++) {
            DutchOutput memory output = order.baseOutputs[i];
            uint256 outputAmount = order.cosignerData.outputAmounts[i];
            if (outputAmount != 0) {
                if (outputAmount < output.startAmount) {
                    revert InvalidCosignerOutput();
                }
                output.startAmount = outputAmount;
            }
        }
    }

    /// @notice validate the dutch order fields
    /// - deadline must be greater than or equal than decayEndTime
    /// - decayEndTime must be greater than or equal to decayStartTime
    /// - if there's input decay, outputs must not decay
    /// @dev Throws if the order is invalid
    function _validateOrder(bytes32 orderHash, V2DutchOrder memory order) internal pure {
        if (order.info.deadline < order.cosignerData.decayEndTime) {
            revert DeadlineBeforeEndTime();
        }

        if (order.cosignerData.decayEndTime <= order.cosignerData.decayStartTime) {
            revert DutchDecayLib.EndTimeBeforeStartTime();
        }

        (bytes32 r, bytes32 s) = abi.decode(order.cosignature, (bytes32, bytes32));
        uint8 v = uint8(order.cosignature[64]);
        // cosigner signs over (orderHash || cosignerData)
        address signer = ecrecover(keccak256(abi.encodePacked(orderHash, abi.encode(order.cosignerData))), v, r, s);
        if (order.cosigner != signer && signer != address(0)) {
            revert InvalidCosignature();
        }

        if (order.baseInput.startAmount != order.baseInput.endAmount) {
            for (uint256 i = 0; i < order.baseOutputs.length; i++) {
                DutchOutput memory output = order.baseOutputs[i];
                if (output.startAmount != output.endAmount) {
                    revert InputAndOutputDecay();
                }
            }
        }
    }
}
