// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {OutputToken, InputToken} from "../base/ReactorStructs.sol";
import {V3DutchOutput, V3DutchInput, V3Decay} from "../lib/V3DutchOrderLib.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {sub} from "./MathExt.sol";
import {Uint16Array, fromUnderlying} from "../types/Uint16Array.sol";

/// @notice thrown when the decay curve is invalid
error InvalidDecayCurve();

/// @notice helpers for handling non-linear dutch order objects
library V3DutchDecayLib {

    using FixedPointMathLib for uint256;
    using {sub} for uint256;

    /// @notice locates the current position on the curve and calculates the decay
    /// @param curve The curve to search
    /// @param startAmount The absolute start amount
    /// @param decayStartBlock The absolute start block of the decay
    function decay(V3Decay memory curve, uint256 startAmount, uint256 decayStartBlock)
        internal
        view
        returns (uint256 decayedAmount)
    {
        // mismatch of relativeAmounts and relativeBlocks
        if(curve.relativeAmounts.length > 16) {
            revert InvalidDecayCurve();
        }

        // handle current block before decay or no decay
        if (decayStartBlock >= block.number || curve.relativeAmounts.length == 0) {
            return startAmount;
        }
        Uint16Array relativeBlocks = fromUnderlying(curve.relativeBlocks);
        uint16 blockDelta = uint16(block.number - decayStartBlock);
        // Special case for when we need to use the decayStartBlock (0)
        if (relativeBlocks.getElement(0) > blockDelta) {
            return linearDecay(0, relativeBlocks.getElement(0), blockDelta, startAmount, startAmount.sub(curve.relativeAmounts[0]));
        }
        // the current pos is within or after the curve
        uint16 prev;
        uint16 next;
        (prev, next) = locateCurvePosition(curve, blockDelta);
        uint256 lastAmount = startAmount.sub(curve.relativeAmounts[prev]);
        uint256 nextAmount = startAmount.sub(curve.relativeAmounts[next]);
        return linearDecay(relativeBlocks.getElement(prev), relativeBlocks.getElement(next), blockDelta, lastAmount, nextAmount);
    }

    /// @notice Locates the current position on the curve using a binary search
    /// @param curve The curve to search
    /// @param currentRelativeBlock The current relative position
    /// @return prev The relative block before the current position
    /// @return next The relative block after the current position
    function locateCurvePosition(V3Decay memory curve, uint16 currentRelativeBlock)
        internal
        pure
        returns (uint16 prev, uint16 next)
    {
        Uint16Array relativeBlocks = fromUnderlying(curve.relativeBlocks);
        prev = 0;
        next = 0;
        while(next < curve.relativeAmounts.length) {
            if (relativeBlocks.getElement(next) >= currentRelativeBlock) {
                return (prev, next);
            }
            prev = next;
            next++;
        }
        return (next - 1, next - 1);
    }

    /// @notice returns the linear interpolation between the two points
    /// @param startBlock The start of the decay
    /// @param endBlock The end of the decay
    /// @param currentBlock The current position in the decay
    /// @param startAmount The amount of the start of the decay
    /// @param endAmount The amount of the end of the decay
    function linearDecay(
        uint16 startBlock,
        uint16 endBlock,
        uint16 currentBlock,
        uint256 startAmount,
        uint256 endAmount
    ) internal pure returns (uint256) {
        if (currentBlock >= endBlock) {
            return endAmount;
        }
        unchecked {
            uint256 elapsed = currentBlock - startBlock;
            uint256 duration = endBlock - startBlock;
            if (endAmount < startAmount) {
                return startAmount - (startAmount - endAmount).mulDivDown(elapsed, duration);
            } else {
                return startAmount + (endAmount - startAmount).mulDivUp(elapsed, duration);
            }
        }
    }

    /// @notice returns a decayed output using the given dutch spec and times
    /// @param output The output to decay
    /// @param decayStartBlock The block to start decaying
    /// @return result a decayed output
    function decay(V3DutchOutput memory output, uint256 decayStartBlock)
        internal
        view
        returns (OutputToken memory result)
    {
        uint256 decayedOutput = V3DutchDecayLib.decay(output.curve, output.startAmount, decayStartBlock);
        result = OutputToken(output.token, decayedOutput, output.recipient);
    }

    /// @notice returns a decayed output array using the given dutch spec and times
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
        uint256 decayedInput = V3DutchDecayLib.decay(input.curve, input.startAmount, decayStartBlock);
        result = InputToken(input.token, decayedInput, input.maxAmount);
    }
}
