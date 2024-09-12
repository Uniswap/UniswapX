// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {OutputToken, InputToken} from "../base/ReactorStructs.sol";
import {V3DutchOutput, V3DutchInput, NonlinearDutchDecay} from "../lib/V3DutchOrderLib.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {MathExt} from "./MathExt.sol";
import {Uint16ArrayLibrary, Uint16Array, fromUnderlying} from "../types/Uint16Array.sol";
import {DutchDecayLib} from "./DutchDecayLib.sol";

/// @notice helpers for handling non-linear dutch order objects
library NonlinearDutchDecayLib {
    using FixedPointMathLib for uint256;
    using MathExt for uint256;
    using Uint16ArrayLibrary for Uint16Array;

    /// @notice thrown when the decay curve is invalid
    error InvalidDecayCurve();

    /// @notice locates the current position on the curve and calculates the decay
    /// @param curve The curve to search
    /// @param startAmount The absolute start amount
    /// @param decayStartBlock The absolute start block of the decay
    /// @dev Expects the relativeBlocks in curve to be strictly increasing
    function decay(
        NonlinearDutchDecay memory curve,
        uint256 startAmount,
        uint256 decayStartBlock,
        uint256 minAmount,
        uint256 maxAmount
    ) internal view returns (uint256 decayedAmount) {
        // mismatch of relativeAmounts and relativeBlocks
        if (curve.relativeAmounts.length > 16) {
            revert InvalidDecayCurve();
        }

        // handle current block before decay or no decay
        if (decayStartBlock >= block.number || curve.relativeAmounts.length == 0) {
            return startAmount.bound(minAmount, maxAmount);
        }
        Uint16Array relativeBlocks = fromUnderlying(curve.relativeBlocks);
        uint16 blockDelta = uint16(block.number - decayStartBlock);
        int256 curveDelta;
        // Special case for when we need to use the decayStartBlock (0)
        if (relativeBlocks.getElement(0) > blockDelta) {
            curveDelta =
                DutchDecayLib.linearDecay(0, relativeBlocks.getElement(0), blockDelta, 0, curve.relativeAmounts[0]);
        } else {
            // the current pos is within or after the curve
            (uint16 prev, uint16 next) = locateCurvePosition(curve, blockDelta);
            // get decay of only the relative amounts
            curveDelta = DutchDecayLib.linearDecay(
                relativeBlocks.getElement(prev),
                relativeBlocks.getElement(next),
                blockDelta,
                curve.relativeAmounts[prev],
                curve.relativeAmounts[next]
            );
        }
        return startAmount.boundedSub(curveDelta, minAmount, maxAmount);
    }

    /// @notice Locates the current position on the curve using a binary search
    /// @param curve The curve to search
    /// @param currentRelativeBlock The current relative position
    /// @return prev The relative block before the current position
    /// @return next The relative block after the current position
    function locateCurvePosition(NonlinearDutchDecay memory curve, uint16 currentRelativeBlock)
        internal
        pure
        returns (uint16 prev, uint16 next)
    {
        Uint16Array relativeBlocks = fromUnderlying(curve.relativeBlocks);
        uint16 curveLength = uint16(curve.relativeAmounts.length);
        for (; next < curveLength; next++) {
            if (relativeBlocks.getElement(next) >= currentRelativeBlock) {
                return (prev, next);
            }
            prev = next;
        }
        return (next - 1, next - 1);
    }

    /// @notice returns a decayed output using the given dutch spec and blocks
    /// @param output The output to decay
    /// @param decayStartBlock The block to start decaying
    /// @return result a decayed output
    function decay(V3DutchOutput memory output, uint256 decayStartBlock)
        internal
        view
        returns (OutputToken memory result)
    {
        uint256 decayedOutput =
            decay(output.curve, output.startAmount, decayStartBlock, output.minAmount, type(uint256).max);
        result = OutputToken(output.token, decayedOutput, output.recipient);
    }

    /// @notice returns a decayed output array using the given dutch spec and blocks
    /// @param outputs The output array to decay
    /// @param decayStartBlock The block to start decaying
    /// @return result a decayed output array
    function decay(V3DutchOutput[] memory outputs, uint256 decayStartBlock)
        internal
        view
        returns (OutputToken[] memory result)
    {
        uint256 outputLength = outputs.length;
        result = new OutputToken[](outputLength);
        unchecked {
            for (uint256 i = 0; i < outputLength; i++) {
                result[i] = decay(outputs[i], decayStartBlock);
            }
        }
    }

    /// @notice returns a decayed input using the given dutch spec and times
    /// @param input The input to decay
    /// @param decayStartBlock The block to start decaying
    /// @return result a decayed input
    function decay(V3DutchInput memory input, uint256 decayStartBlock)
        internal
        view
        returns (InputToken memory result)
    {
        uint256 decayedInput = decay(input.curve, input.startAmount, decayStartBlock, 0, input.maxAmount);
        result = InputToken(input.token, decayedInput, input.maxAmount);
    }
}
