// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {BaseReactor} from "./BaseReactor.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {Permit2Lib} from "../lib/Permit2Lib.sol";
import {ExclusivityLib} from "../lib/ExclusivityLib.sol";
import {NonlinearDutchDecayLib} from "../lib/NonlinearDutchDecayLib.sol";
import {V3DutchOrderLib, V3DutchOrder, CosignerData, V3DutchOutput, V3DutchInput} from "../lib/V3DutchOrderLib.sol";
import {SignedOrder, ResolvedOrder} from "../base/ReactorStructs.sol";
import {BlockNumberish} from "../base/BlockNumberish.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {MathExt} from "../lib/MathExt.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {CosignerLib} from "../lib/CosignerLib.sol";

/// @notice Reactor for V3 dutch orders
/// @dev V3 orders must be cosigned by the specified cosigner to set the starting block and override the value
/// @dev resolution behavior:
/// - If cosignature is invalid or not from specified cosigner, revert
/// - If inputAmount is 0, then use baseInput
/// - If inputAmount is nonzero, then ensure it is less than specified baseInput and replace startAmount
/// - For each outputAmount:
///   - If amount is 0, then use baseOutput
///   - If amount is nonzero, then ensure it is greater than specified baseOutput and replace startAmount
contract V3DutchOrderReactor is BaseReactor, BlockNumberish {
    using Permit2Lib for ResolvedOrder;
    using V3DutchOrderLib for V3DutchOrder;
    using NonlinearDutchDecayLib for V3DutchOutput[];
    using NonlinearDutchDecayLib for V3DutchInput;
    using ExclusivityLib for ResolvedOrder;
    using FixedPointMathLib for uint256;
    using MathExt for uint256;

    /// @notice thrown when an order's deadline is passed
    error DeadlineReached();

    /// @notice thrown when an order's cosigner input is greater than the specified
    error InvalidCosignerInput();

    /// @notice thrown when an order's cosigner output is less than the specified
    error InvalidCosignerOutput();

    constructor(IPermit2 _permit2, address _protocolFeeOwner)
        BaseReactor(_permit2, _protocolFeeOwner)
        BlockNumberish()
    {}

    /// @inheritdoc BaseReactor
    function _resolve(SignedOrder calldata signedOrder)
        internal
        view
        virtual
        override
        returns (ResolvedOrder memory resolvedOrder)
    {
        V3DutchOrder memory order = abi.decode(signedOrder.order, (V3DutchOrder));
        // hash the order _before_ overriding amounts, as this is the hash the user would have signed
        bytes32 orderHash = order.hash();

        _validateOrder(orderHash, order);
        _updateWithCosignerAmounts(order);
        _updateWithGasAdjustment(order);

        uint256 blockNumberish = _getBlockNumberish();

        resolvedOrder = ResolvedOrder({
            info: order.info,
            input: order.baseInput.decay(order.cosignerData.decayStartBlock, blockNumberish),
            outputs: order.baseOutputs.decay(order.cosignerData.decayStartBlock, blockNumberish),
            sig: signedOrder.sig,
            hash: orderHash,
            auctionResolver: address(0)
        });
        resolvedOrder.handleExclusiveOverrideBlock(
            order.cosignerData.exclusiveFiller,
            order.cosignerData.decayStartBlock,
            order.cosignerData.exclusivityOverrideBps,
            blockNumberish
        );
    }

    /// @inheritdoc BaseReactor
    function _transferInputTokens(ResolvedOrder memory order, address to) internal override {
        permit2.permitWitnessTransferFrom(
            order.toPermit(),
            order.transferDetails(to),
            order.info.swapper,
            order.hash,
            V3DutchOrderLib.PERMIT2_ORDER_TYPE,
            order.sig
        );
    }

    function _updateWithCosignerAmounts(V3DutchOrder memory order) internal pure {
        if (order.cosignerData.inputAmount != 0) {
            if (order.cosignerData.inputAmount > order.baseInput.startAmount) {
                revert InvalidCosignerInput();
            }
            order.baseInput.startAmount = order.cosignerData.inputAmount;
        }

        if (order.cosignerData.outputAmounts.length != order.baseOutputs.length) {
            revert InvalidCosignerOutput();
        }
        uint256 outputsLength = order.baseOutputs.length;
        for (uint256 i = 0; i < outputsLength; i++) {
            V3DutchOutput memory output = order.baseOutputs[i];
            uint256 outputAmount = order.cosignerData.outputAmounts[i];
            if (outputAmount != 0) {
                if (outputAmount < output.startAmount) {
                    revert InvalidCosignerOutput();
                }
                output.startAmount = outputAmount;
            }
        }
    }

    function _updateWithGasAdjustment(V3DutchOrder memory order) internal view {
        // Positive means an increase in gas
        int256 gasDeltaWei = block.basefee.sub(order.startingBaseFee);
        // Gas increase should increase input
        if (order.baseInput.adjustmentPerGweiBaseFee != 0) {
            // Round in favor of swapper
            int256 inputDelta = _computeDelta(order.baseInput.adjustmentPerGweiBaseFee, gasDeltaWei);
            order.baseInput.startAmount =
                order.baseInput.startAmount.boundedAdd(inputDelta, 0, order.baseInput.maxAmount);
        }
        // Gas increase should decrease output
        uint256 outputsLength = order.baseOutputs.length;
        for (uint256 i = 0; i < outputsLength; i++) {
            V3DutchOutput memory output = order.baseOutputs[i];
            if (output.adjustmentPerGweiBaseFee != 0) {
                // Round in favor of swapper
                int256 outputDelta = _computeDelta(output.adjustmentPerGweiBaseFee, gasDeltaWei);
                output.startAmount = output.startAmount.boundedSub(outputDelta, output.minAmount, type(uint256).max);
            }
        }
    }

    function _computeDelta(uint256 adjustmentPerGweiBaseFee, int256 gasDeltaWei) internal pure returns (int256) {
        if (gasDeltaWei >= 0) {
            // Gas increase: round adjustment down to decrease amount added to input or subtracted from output
            return int256(adjustmentPerGweiBaseFee.mulDivDown(uint256(gasDeltaWei), 1 gwei));
        } else {
            // Gas decrease: round adjustment up to increase amount added to output or subtracted from input
            return -int256(adjustmentPerGweiBaseFee.mulDivUp(uint256(-gasDeltaWei), 1 gwei));
        }
    }

    /// @notice validate the dutch order fields
    /// - deadline must have not passed
    /// - cosigner must always be provided and sign the cosignerData
    /// @dev Throws if the order is invalid
    function _validateOrder(bytes32 orderHash, V3DutchOrder memory order) internal view {
        if (order.info.deadline < block.timestamp) {
            revert DeadlineReached();
        }

        CosignerLib.verify(order.cosigner, order.cosignerDigest(orderHash), order.cosignature);
    }
}
