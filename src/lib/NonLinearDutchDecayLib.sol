// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {OutputToken, InputToken} from "../base/ReactorStructs.sol";
import {NonLinearDutchOutput, NonLinearDutchInput, NonLinearDecay} from "../lib/NonLinearDutchOrderLib.sol";
import {SafeMath} from "./SafeMath.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";

/// @notice helpers for handling dutch order objects
library NonLinearDutchDecayLib {
    using FixedPointMathLib for uint256;

    /// @notice thrown if the decay direction is incorrect
    /// - for DutchInput, startAmount must be less than or equal to endAmount
    /// - for DutchOutput, startAmount must be greater than or equal to endAmount
    error IncorrectAmounts();

    /// @notice thrown if the curve blocks are not strictly increasing
    error InvalidDecay();

    struct CurveSegment {
        uint256 startAmount;
        uint256 endAmount;
        uint256 decayStartBlock;
        uint256 decayEndBlock;
    }

    /// @notice locates the surrounding points on the curve
    function decay(NonLinearDecay memory curve, uint256 startAmount, uint256 decayStartBlock)
        internal
        view
        returns (uint256 decayedAmount)
    {
        // handle current block before decay or no decay
        if (decayStartBlock >= block.number || curve.relativeBlock.length == 0) {
            return startAmount;
        }
        uint256 blockDelta = block.number - decayStartBlock;
        // iterate through the points and locate the current segment
        for (uint256 i = 0; i < curve.relativeBlock.length; i++) {
            if (curve.relativeBlock[i] >= blockDelta) {
                uint256 lastAmount = startAmount;
                uint256 startBlock = decayStartBlock;
                if (i != 0) {
                    // Ensure valid decay
                    if (curve.relativeBlock[i] <= curve.relativeBlock[i-1]) {
                        revert InvalidDecay();
                    }
                    lastAmount = SafeMath.addIntToUint(startAmount, curve.relativeAmount[i-1]);
                    startBlock = curve.relativeBlock[i-1];
                }
                uint256 nextAmount = SafeMath.addIntToUint(curve.relativeAmount[i], lastAmount);
                // linear interpolation between the two points
                unchecked {
                    uint256 elapsed = blockDelta - startBlock;
                    uint256 duration = curve.relativeBlock[i] - startBlock;
                    if (nextAmount < lastAmount) {
                        return lastAmount - (lastAmount - nextAmount).mulDivDown(elapsed, duration);
                    } else {
                        return lastAmount + (nextAmount - lastAmount).mulDivUp(elapsed, duration);
                    }
                }
            }
        }
        // handle current block after last decay block
        decayedAmount = curve.relativeAmount[curve.relativeAmount.length - 1];
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
        result = InputToken(input.token, decayedInput, input.endAmount);
    }
}
