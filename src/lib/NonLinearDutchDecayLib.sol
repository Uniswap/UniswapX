// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {OutputToken, InputToken} from "../base/ReactorStructs.sol";
import {NonLinearDutchOutput, NonLinearDutchInput, NonLinearDecay} from "../lib/NonLinearDutchOrderLib.sol";
import {Util} from "./Util.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";

/// @notice helpers for handling dutch order objects
library NonLinearDutchDecayLib {
    using FixedPointMathLib for uint256;

    /// @notice locates the surrounding points on the curve
    function decay(NonLinearDecay memory curve, uint256 startAmount, uint256 decayStartBlock)
        internal
        view
        returns (uint256 decayedAmount)
    {
        // handle current block before decay or no decay
        if (decayStartBlock >= block.number) {
            return startAmount;
        }
        uint256 blockDelta = block.number - decayStartBlock;
        // iterate through the points and locate the current segment
        for (uint256 i = 0; i < curve.relativeAmount.length; i++) {
            // relativeBlocks is an array of uint16 packed one uint256
            uint16 relativeBlock = Util.getUint16FromPacked(curve.relativeBlocks, i);
            if (relativeBlock >= blockDelta) {
                uint256 lastAmount = startAmount;
                uint16 relativeStartBlock = 0;
                if (i != 0) {
                    lastAmount = Util.subIntFromUint(curve.relativeAmount[i-1], startAmount);
                    relativeStartBlock = Util.getUint16FromPacked(curve.relativeBlocks, i-1);
                }
                uint256 nextAmount = Util.subIntFromUint(curve.relativeAmount[i], startAmount);
                // linear interpolation between the two points
                unchecked {
                    uint256 elapsed = blockDelta - relativeStartBlock;
                    uint256 duration = relativeBlock - relativeStartBlock;
                    if (nextAmount < lastAmount) {
                        return lastAmount - (lastAmount - nextAmount).mulDivDown(elapsed, duration);
                    } else {
                        return lastAmount + (nextAmount - lastAmount).mulDivUp(elapsed, duration);
                    }
                }
            }
        }
        // handle current block after last decay block
        decayedAmount = Util.subIntFromUint(curve.relativeAmount[curve.relativeAmount.length - 1], startAmount);
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
