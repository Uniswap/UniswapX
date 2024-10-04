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
        uint256 maxAmount,
        bool isInput
    ) internal view returns (uint256 decayedAmount) {
        // mismatch of relativeAmounts and relativeBlocks
        if (curve.relativeAmounts.length > 16) {
            revert InvalidDecayCurve();
        }

        // handle current block before decay or no decay
        if (decayStartBlock >= block.number || curve.relativeAmounts.length == 0) {
            return startAmount.bound(minAmount, maxAmount);
        }

        uint16 blockDelta = uint16(block.number - decayStartBlock);
        (uint16 startPoint, uint16 endPoint, int256 relStartAmount, int256 relEndAmount) =
            locateCurvePosition(curve, blockDelta);
        // get decay of only the relative amounts
        int256 curveDelta =
            v3LinearDecay(startPoint, endPoint, blockDelta, relStartAmount, relEndAmount, isInput);

        return startAmount.boundedSub(curveDelta, minAmount, maxAmount);
    }

    /// @notice Locates the current position on the curve
    /// @param curve The curve to search
    /// @param currentRelativeBlock The current relative position
    /// @return startPoint The relative block before the current position
    /// @return endPoint The relative block after the current position
    /// @return startAmount The relative amount before the current position
    /// @return endAmount The relative amount after the current position
    function locateCurvePosition(NonlinearDutchDecay memory curve, uint16 currentRelativeBlock)
        internal
        pure
        returns (uint16 startPoint, uint16 endPoint, int256 startAmount, int256 endAmount)
    {
        Uint16Array relativeBlocks = fromUnderlying(curve.relativeBlocks);
        // Position is before the start of the curve
        if (relativeBlocks.getElement(0) >= currentRelativeBlock) {
            return (0, relativeBlocks.getElement(0), 0, curve.relativeAmounts[0]);
        }
        uint16 lastCurveIndex = uint16(curve.relativeAmounts.length) - 1;
        for (uint16 i = 1; i <= lastCurveIndex; i++) {
            if (relativeBlocks.getElement(i) >= currentRelativeBlock) {
                return (
                    relativeBlocks.getElement(i - 1),
                    relativeBlocks.getElement(i),
                    curve.relativeAmounts[i - 1],
                    curve.relativeAmounts[i]
                );
            }
        }

        return (
            relativeBlocks.getElement(lastCurveIndex),
            relativeBlocks.getElement(lastCurveIndex),
            curve.relativeAmounts[lastCurveIndex],
            curve.relativeAmounts[lastCurveIndex]
        );
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
            decay(output.curve, output.startAmount, decayStartBlock, output.minAmount, type(uint256).max, false);
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
        for (uint256 i = 0; i < outputLength; i++) {
            result[i] = decay(outputs[i], decayStartBlock);
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
        uint256 decayedInput = decay(input.curve, input.startAmount, decayStartBlock, 0, input.maxAmount, true);
        result = InputToken(input.token, decayedInput, input.maxAmount);
    }

    /// @notice returns the linear interpolation between the two points
    /// @param startPoint The start of the decay
    /// @param endPoint The end of the decay
    /// @param currentPoint The current position in the decay
    /// @param startAmount The amount of the start of the decay
    /// @param endAmount The amount of the end of the decay
    /// @dev rounds in favor of the swapper based on input or output
    function v3LinearDecay(
        uint256 startPoint,
        uint256 endPoint,
        uint256 currentPoint,
        int256 startAmount,
        int256 endAmount,
        bool isInput
    ) internal pure returns (int256) {
        if (currentPoint >= endPoint) {
            return endAmount;
        }
        uint256 elapsed = currentPoint - startPoint;
        uint256 duration = endPoint - startPoint;
        int256 delta;
        if (isInput) {
            // Because startAmount + delta is subtracted from the original amount,
            // we want to maximize startAmount + delta to favor the swapper
            if (endAmount < startAmount) {
                delta = -int256(uint256(startAmount - endAmount).mulDivDown(elapsed, duration));
            } else {
                delta = int256(uint256(endAmount - startAmount).mulDivUp(elapsed, duration));
            }
        } else {
            // For outputs, we want to minimize startAmount + delta to favor the swapper
            if (endAmount < startAmount) {
                delta = -int256(uint256(startAmount - endAmount).mulDivUp(elapsed, duration));
            } else {
                delta = int256(uint256(endAmount - startAmount).mulDivDown(elapsed, duration));
            }
        }

        return startAmount + delta;
    }
}
