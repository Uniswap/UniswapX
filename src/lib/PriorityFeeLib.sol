// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {OutputToken, InputToken} from "../base/ReactorStructs.sol";
import {PriorityOutput, PriorityInput} from "../lib/PriorityOrderLib.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";

/// @notice helpers for handling priority order objects
library PriorityFeeLib {
    using FixedPointMathLib for uint256;

    /// @notice we denominate priority fees in terms of milli-bips, or one thousandth of a basis point
    uint256 constant MPS = 1e7;

    /// @notice returns a scaled input using the current priority fee and mpsPerPriorityFeeWei
    /// @notice this value is bounded by 0 and the input amount
    /// @notice the amount is scaled down to favor the swapper
    /// @notice maxAmount is set to be the original amount and is used to rebuild the permit2 token permissions struct
    /// @param input the input to scale
    /// @param priorityFee the current priority fee in wei
    /// @return a scaled input
    function scale(PriorityInput memory input, uint256 priorityFee) internal pure returns (InputToken memory) {
        uint256 scalingFactor = priorityFee * input.mpsPerPriorityFeeWei;
        if (scalingFactor >= MPS) {
            return InputToken({token: input.token, amount: 0, maxAmount: input.amount});
        }
        return InputToken({token: input.token, amount: input.amount.mulDivDown((MPS - scalingFactor), MPS), maxAmount: input.amount});
    }

    /// @notice returns a scaled output using the current priority fee and mpsPerPriorityFeeWei
    /// @notice the amount is scaled up to favor the swapper
    /// @param output the output to scale
    /// @param priorityFee the current priority fee
    /// @return a scaled output
    function scale(PriorityOutput memory output, uint256 priorityFee) internal pure returns (OutputToken memory) {
        return OutputToken({
            token: output.token,
            amount: output.amount.mulDivUp((MPS + (priorityFee * output.mpsPerPriorityFeeWei)), MPS),
            recipient: output.recipient
        });
    }

    /// @notice returns scaled outputs using the current priority fee and mpsPerPriorityFeeWei
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
