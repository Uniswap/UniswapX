// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {OutputToken, InputToken} from "../base/ReactorStructs.sol";
import {PriorityOutput, PriorityInput} from "../lib/PriorityOrderLib.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";

/// @notice helpers for handling priority order objects
library PriorityFeeLib {
    using FixedPointMathLib for uint256;

    uint256 constant BPS = 10_000;

    /// @notice scales the amount by bpsPerPriorityFee for every wei of priorityFeeWei
    function scale(uint256 amount, uint256 bpsPerPriorityFeeWei, uint256 priorityFeeWei)
        internal
        pure
        returns (uint256)
    {
        if (bpsPerPriorityFeeWei == 0 || priorityFeeWei == 0) return amount;
        return amount.mulDivUp((BPS + (priorityFeeWei * bpsPerPriorityFeeWei)), BPS);
    }

    /// @notice returns a scaled input using the current priority fee and bpsPerPriorityFeeWei
    /// @notice the amount is scaled down to favor the swapper
    /// @param input the input to scale
    /// @param bpsPerPriorityFeeWei the amount of bps to scale by
    /// @param priorityFee the current priority fee
    /// @return a scaled input
    function scale(PriorityInput memory input, uint256 bpsPerPriorityFeeWei, uint256 priorityFee)
        internal
        pure
        returns (InputToken memory)
    {
        uint256 scaledAmount = input.amount.mulDivDown((BPS - (priorityFee * bpsPerPriorityFeeWei)), BPS);
        return InputToken({token: input.token, amount: scaledAmount, maxAmount: scaledAmount});
    }

    /// @notice returns a scaled output using the current priority fee and bpsPerPriorityFeeWei
    /// @notice the amount is scaled up to favor the swapper
    /// @param output the output to scale
    /// @param bpsPerPriorityFeeWei the amount of bps to scale by
    /// @param priorityFee the current priority fee
    /// @return a scaled output
    function scale(PriorityOutput memory output, uint256 bpsPerPriorityFeeWei, uint256 priorityFee)
        internal
        pure
        returns (OutputToken memory)
    {
        return OutputToken({
            token: output.token,
            amount: output.amount.mulDivUp((BPS + (priorityFee * bpsPerPriorityFeeWei)), BPS),
            recipient: output.recipient
        });
    }

    /// @notice returns scaled outputs using the current priority fee and bpsPerPriorityFeeWei
    function scale(PriorityOutput[] memory outputs, uint256 bpsPerPriorityFeeWei, uint256 priorityFee)
        internal
        pure
        returns (OutputToken[] memory result)
    {
        uint256 outputLength = outputs.length;
        result = new OutputToken[](outputLength);
        unchecked {
            for (uint256 i = 0; i < outputLength; i++) {
                result[i] = scale(outputs[i], bpsPerPriorityFeeWei, priorityFee);
            }
        }
    }
}
