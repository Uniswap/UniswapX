// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {OutputToken, InputToken} from "../base/ReactorStructs.sol";
import {NonLinearDutchOutput, NonLinearDutchInput, NonLinearDecay} from "../lib/NonLinearDutchOrderLib.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {sub} from "./MathExt.sol";
import {Uint16Array, fromUnderlying} from "../types/Uint16Array.sol";

/// @notice helpers for handling non-linear dutch order objects
library NonLinearDutchDecayLib {
    using FixedPointMathLib for uint256;
    using {sub} for uint256;

    /// @notice locates the current position on the curve and calculates the decay
    function decay(NonLinearDecay memory curve, uint256 startAmount, uint256 decayStartBlock)
        internal
        view
        returns (uint256 decayedAmount)
    {
        // handle current block before decay or no decay
        if (decayStartBlock >= block.number) {
            return startAmount;
        }
        uint16 blockDelta = uint16(block.number - decayStartBlock);
        // iterate through the points and locate the current segment
        for (uint16 i = 0; i < curve.relativeAmounts.length; i++) {
            // relativeBlocks is an array of uint16 packed one uint256
            Uint16Array relativeBlocks = fromUnderlying(curve.relativeBlocks);
            uint16 relativeBlock = relativeBlocks.getElement(i);
            if (relativeBlock >= blockDelta) {
                uint256 lastAmount = startAmount;
                uint16 relativeStartBlock = 0;
                if (i != 0) {
                    lastAmount = startAmount.sub(curve.relativeAmounts[i - 1]);
                    relativeStartBlock = relativeBlocks.getElement(i - 1);
                }
                uint256 nextAmount = startAmount.sub(curve.relativeAmounts[i]);
                return linearDecay(relativeStartBlock, relativeBlock, blockDelta, lastAmount, nextAmount);
            }
        }
        // handle current block after last decay block
        decayedAmount = startAmount.sub(curve.relativeAmounts[curve.relativeAmounts.length - 1]);
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
    function decay(NonLinearDutchOutput memory output, uint256 decayStartBlock)
        internal
        view
        returns (OutputToken memory result)
    {
        uint256 decayedOutput = NonLinearDutchDecayLib.decay(output.curve, output.startAmount, decayStartBlock);
        result = OutputToken(output.token, decayedOutput, output.recipient);
    }

    /// @notice returns a decayed output array using the given dutch spec and times
    /// @param outputs The output array to decay
    /// @param decayStartBlock The block to start decaying
    /// @return result a decayed output array
    function decay(NonLinearDutchOutput[] memory outputs, uint256 decayStartBlock)
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
    function decay(NonLinearDutchInput memory input, uint256 decayStartBlock)
        internal
        view
        returns (InputToken memory result)
    {
        uint256 decayedInput = NonLinearDutchDecayLib.decay(input.curve, input.startAmount, decayStartBlock);
        result = InputToken(input.token, decayedInput, input.maxAmount);
    }
}
