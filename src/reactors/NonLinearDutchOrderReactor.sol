// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {BaseReactor} from "./BaseReactor.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {Permit2Lib} from "../lib/Permit2Lib.sol";
import {ExclusivityLib} from "../lib/ExclusivityLib.sol";
import {NonLinearDutchDecayLib} from "../lib/NonLinearDutchDecayLib.sol";
import {NonLinearDutchOrderLib, NonLinearDutchOrder, CosignerData, NonLinearDutchOutput, NonLinearDutchInput} from "../lib/NonLinearDutchOrderLib.sol";
import {SignedOrder, ResolvedOrder} from "../base/ReactorStructs.sol";

/// @notice Reactor for non-linear dutch orders
/// @dev V2 orders must be cosigned by the specified cosigner to override timings and starting values
/// @dev resolution behavior:
/// - If cosignature is invalid or not from specified cosigner, revert
/// - If inputAmount is 0, then use baseInput
/// - If inputAmount is nonzero, then ensure it is less than specified baseInput and replace startAmount
/// - For each outputAmount:
///   - If amount is 0, then use baseOutput
///   - If amount is nonzero, then ensure it is greater than specified baseOutput and replace startAmount
contract NonLinearDutchOrderReactor is BaseReactor {
    using Permit2Lib for ResolvedOrder;
    using NonLinearDutchOrderLib for NonLinearDutchOrder;
    using NonLinearDutchDecayLib for NonLinearDutchOutput[];
    using NonLinearDutchDecayLib for NonLinearDutchInput;
    using ExclusivityLib for ResolvedOrder;

    /// @notice thrown when an order's deadline is before its end block
    error DeadlineBeforeEndBlock();

    /// @notice thrown when an order's cosignature does not match the expected cosigner
    error InvalidCosignature();

    /// @notice thrown when an order's cosigner input is greater than the specified
    error InvalidCosignerInput();

    /// @notice thrown when an order's cosigner output is less than the specified
    error InvalidCosignerOutput();

    constructor(IPermit2 _permit2, address _protocolFeeOwner) BaseReactor(_permit2, _protocolFeeOwner) {}

    /// @inheritdoc BaseReactor
    function _resolve(SignedOrder calldata signedOrder)
        internal
        view
        virtual
        override
        returns (ResolvedOrder memory resolvedOrder)
    {
        NonLinearDutchOrder memory order = abi.decode(signedOrder.order, (NonLinearDutchOrder));
        // hash the order _before_ overriding amounts, as this is the hash the user would have signed
        bytes32 orderHash = order.hash();

        _validateOrder(orderHash, order);
        _updateWithCosignerAmounts(order);

        resolvedOrder = ResolvedOrder({
            info: order.info,
            input: order.baseInput.decay(order.cosignerData.decayStartBlock),
            outputs: order.baseOutputs.decay(order.cosignerData.decayStartBlock),
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
    function _transferInputTokens(ResolvedOrder memory order, address to) internal override {
        permit2.permitWitnessTransferFrom(
            order.toPermit(),
            order.transferDetails(to),
            order.info.swapper,
            order.hash,
            NonLinearDutchOrderLib.PERMIT2_ORDER_TYPE,
            order.sig
        );
    }

    function _updateWithCosignerAmounts(NonLinearDutchOrder memory order) internal pure {
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
            NonLinearDutchOutput memory output = order.baseOutputs[i];
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
    /// - deadline must be greater than or equal to decayEndBlock
    /// - if there's input decay, outputs must not decay
    /// @dev Throws if the order is invalid
    function _validateOrder(bytes32 orderHash, NonLinearDutchOrder memory order) internal pure {
        uint256 relativeDecayEndBlock = order.info.relativeBlock.length == 0 
            ? 0
            : order.info.relativeBlock[order.info.relativeBlock.length-1];
        if (order.info.deadline < order.cosignerData.decayStartBlock + relativeDecayEndBlock) {
            revert DeadlineBeforeEndBlock();
        }

        (bytes32 r, bytes32 s) = abi.decode(order.cosignature, (bytes32, bytes32));
        uint8 v = uint8(order.cosignature[64]);
        // cosigner signs over (orderHash || cosignerData)
        address signer = ecrecover(keccak256(abi.encodePacked(orderHash, abi.encode(order.cosignerData))), v, r, s);
        if (order.cosigner != signer || signer == address(0)) {
            revert InvalidCosignature();
        }
    }
}
