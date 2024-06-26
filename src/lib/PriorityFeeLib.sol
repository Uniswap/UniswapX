// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {OutputToken, InputToken} from "../base/ReactorStructs.sol";
import {PriorityOutput, PriorityInput} from "../lib/PriorityOrderLib.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";

/// @notice helpers for handling priority order objects
library PriorityFeeLib {
    using FixedPointMathLib for uint256;

    /// @notice we denominate priority fees in terms of pips, or one hundredth of a basis point
    uint256 constant PPS = 1e10;

    /// @notice returns a scaled input using the current priority fee and pipsPerPriorityFeeWei
    /// @notice this value is bounded by 0 since the maximal extractable value is <= the full input amount
    /// @notice the amount is scaled down to favor the swapper
    /// @param input the input to scale
    /// @param priorityFee the current priority fee
    /// @return a scaled input
    function scale(PriorityInput memory input, uint256 priorityFee) internal pure returns (InputToken memory) {
        if (priorityFee * input.pipsPerPriorityFeeWei >= PPS) {
            return InputToken({token: input.token, amount: 0, maxAmount: 0});
        }
        uint256 scaledAmount = input.amount.mulDivDown((PPS - (priorityFee * input.pipsPerPriorityFeeWei)), PPS);
        return InputToken({token: input.token, amount: scaledAmount, maxAmount: scaledAmount});
    }

    /// @notice returns a scaled output using the current priority fee and pipsPerPriorityFeeWei
    /// @notice the amount is scaled up to favor the swapper
    /// @param output the output to scale
    /// @param priorityFee the current priority fee
    /// @return a scaled output
    function scale(PriorityOutput memory output, uint256 priorityFee) internal pure returns (OutputToken memory) {
        return OutputToken({
            token: output.token,
            amount: output.amount.mulDivUp((PPS + (priorityFee * output.pipsPerPriorityFeeWei)), PPS),
            recipient: output.recipient
        });
    }

    /// @notice returns scaled outputs using the current priority fee and pipsPerPriorityFeeWei
    function scale(PriorityOutput[] memory outputs, uint256 priorityFee)
        internal
        pure
        returns (OutputToken[] memory result)
    {
        uint256 outputLength = outputs.length;
        result = new OutputToken[](outputLength);
        for (uint256 i = 0; i < outputLength; i++) {
            result[i] = scale(outputs[i], priorityFee);
        }
    }
}
