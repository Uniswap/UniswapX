// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.19;

import {OutputToken, InputToken} from "../base/ReactorStructs.sol";
import {DutchOutput, DutchInput} from "../lib/DutchLimitOrderLib.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";

/// @notice helpers for handling dutch limit order objects
library DutchDecayLib {
    using FixedPointMathLib for uint256;

    error IncorrectAmounts();
    error EndTimeBeforeStartTime();

    /// @notice calculates an amount using linear decay over time from startTime to endTime
    /// @dev handles both positive and negative decay depending on startAmount and endAmount
    /// @param startAmount The amount of tokens at startTime
    /// @param endAmount The amount of tokens at endTime
    /// @param startTime The time to start decaying linearly
    /// @param endTime The time to stop decaying linearly
    function decay(uint256 startAmount, uint256 endAmount, uint256 startTime, uint256 endTime)
        internal
        view
        returns (uint256 decayedAmount)
    {
        if (endTime < startTime) {
            revert EndTimeBeforeStartTime();
        } else if (endTime < block.timestamp || startAmount == endAmount || startTime == endTime) {
            decayedAmount = endAmount;
        } else if (startTime > block.timestamp) {
            decayedAmount = startAmount;
        } else {
            unchecked {
                uint256 elapsed = block.timestamp - startTime;
                uint256 duration = endTime - startTime;
                if (endAmount < startAmount) {
                    decayedAmount = startAmount - (startAmount - endAmount).mulDivDown(elapsed, duration);
                } else {
                    decayedAmount = startAmount + (endAmount - startAmount).mulDivDown(elapsed, duration);
                }
            }
        }
    }

    /// @notice returns a decayed output using the given dutch spec and times
    /// @param output The output to decay
    /// @param startTime The time to start decaying
    /// @param endTime The time to end decaying
    /// @return result a decayed output
    function decay(DutchOutput memory output, uint256 startTime, uint256 endTime)
        internal
        view
        returns (OutputToken memory result)
    {
        if (output.startAmount < output.endAmount) {
            revert IncorrectAmounts();
        }

        uint256 decayedOutput = DutchDecayLib.decay(output.startAmount, output.endAmount, startTime, endTime);
        result = OutputToken(output.token, decayedOutput, output.recipient);
    }

    /// @notice returns a decayed output array using the given dutch spec and times
    /// @param outputs The output array to decay
    /// @param startTime The time to start decaying
    /// @param endTime The time to end decaying
    /// @return result a decayed output array
    function decay(DutchOutput[] memory outputs, uint256 startTime, uint256 endTime)
        internal
        view
        returns (OutputToken[] memory result)
    {
        uint256 outputLength = outputs.length;
        result = new OutputToken[](outputLength);
        unchecked {
            for (uint256 i = 0; i < outputLength; i++) {
                result[i] = decay(outputs[i], startTime, endTime);
            }
        }
    }

    /// @notice returns a decayed input using the given dutch spec and times
    /// @param input The input to decay
    /// @param startTime The time to start decaying
    /// @param endTime The time to end decaying
    /// @return result a decayed input
    function decay(DutchInput memory input, uint256 startTime, uint256 endTime)
        internal
        view
        returns (InputToken memory result)
    {
        if (input.startAmount > input.endAmount) {
            revert IncorrectAmounts();
        }

        uint256 decayedInput = DutchDecayLib.decay(input.startAmount, input.endAmount, startTime, endTime);
        result = InputToken(input.token, decayedInput, input.endAmount);
    }
}
