// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {InputTokenWithRecipient} from "../base/ReactorStructs.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";

/// @notice helpers for handling dutch order objects
library RelayDecayLib {
    using FixedPointMathLib for uint256;

    /// @notice thrown if the decay direction is incorrect
    /// - for InputTokens, startAmount must be less than or equal toendAmount
    /// - for OutputTokens, startAmount must be greater than or equal to endAmount
    error IncorrectAmounts();

    /// @notice thrown if the endTime of an order is before startTime
    error EndTimeBeforeStartTime();

    /// @notice calculates an amount using linear decay over time from decayStartTime to decayEndTime
    /// @dev handles both positive and negative decay depending on startAmount and endAmount
    /// @param startAmount The amount of tokens at decayStartTime
    /// @param endAmount The amount of tokens at decayEndTime
    /// @param decayStartTime The time to start decaying linearly
    /// @param decayEndTime The time to stop decaying linearly
    function decay(uint256 startAmount, uint256 endAmount, uint256 decayStartTime, uint256 decayEndTime)
        internal
        view
        returns (uint256 decayedAmount)
    {
        if (decayEndTime < decayStartTime) {
            revert EndTimeBeforeStartTime();
        } else if (decayEndTime <= block.timestamp) {
            decayedAmount = endAmount;
        } else if (decayStartTime >= block.timestamp) {
            decayedAmount = startAmount;
        } else {
            unchecked {
                uint256 elapsed = block.timestamp - decayStartTime;
                uint256 duration = decayEndTime - decayStartTime;
                if (endAmount < startAmount) {
                    decayedAmount = startAmount - (startAmount - endAmount).mulDivDown(elapsed, duration);
                } else {
                    decayedAmount = startAmount + (endAmount - startAmount).mulDivDown(elapsed, duration);
                }
            }
        }
    }

    /// @notice returns a decayed input array using the given decay spec and times
    /// @param inputs The input array to decay
    /// @param decayStartTime The time to start decaying
    /// @param decayEndTime The time to end decaying
    /// @return result a decayed input array
    function decay(InputTokenWithRecipient[] memory inputs, uint256 decayStartTime, uint256 decayEndTime)
        internal
        view
        returns (InputTokenWithRecipient[] memory result)
    {
        uint256 inputLength = inputs.length;
        result = new InputTokenWithRecipient[](inputLength);
        unchecked {
            for (uint256 i = 0; i < inputLength; i++) {
                result[i] = decay(inputs[i], decayStartTime, decayEndTime);
            }
        }
    }

    /// @notice returns a decayed input using the given decay spec and times
    /// @param input The input to decay
    /// @param decayStartTime The time to start decaying
    /// @param decayEndTime The time to end decaying
    /// @return result a decayed input
    function decay(InputTokenWithRecipient memory input, uint256 decayStartTime, uint256 decayEndTime)
        internal
        view
        returns (InputTokenWithRecipient memory result)
    {
        if (input.amount > input.maxAmount) {
            revert IncorrectAmounts();
        }

        uint256 decayedInput = RelayDecayLib.decay(input.amount, input.maxAmount, decayStartTime, decayEndTime);
        result = InputTokenWithRecipient(input.token, decayedInput, input.maxAmount, input.recipient);
    }
}
