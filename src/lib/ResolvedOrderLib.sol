// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {OrderInfo, ResolvedOrder, OutputToken} from "../base/ReactorStructs.sol";
import {IValidationCallback} from "../interfaces/IValidationCallback.sol";

library ResolvedOrderLib {
    error InvalidReactor();
    error DeadlinePassed();
    error ValidationFailed();

    /// @notice Validates a resolved order, reverting if invalid
    /// @param filler The filler of the order
    function validate(ResolvedOrder memory resolvedOrder, address filler) internal view {
        if (address(this) != resolvedOrder.info.reactor) {
            revert InvalidReactor();
        }

        if (block.timestamp > resolvedOrder.info.deadline) {
            revert DeadlinePassed();
        }

        if (
            resolvedOrder.info.validationContract != address(0)
                && !IValidationCallback(resolvedOrder.info.validationContract).validate(filler, resolvedOrder)
        ) {
            revert ValidationFailed();
        }
    }

    function getTokenOutputAmount(ResolvedOrder memory resolvedOrder, address token)
        internal
        pure
        returns (uint256 amount)
    {
        OutputToken[] memory outputs = resolvedOrder.outputs;
        for (uint256 i = 0; i < outputs.length;) {
            if (outputs[i].token == token) {
                amount += outputs[i].amount;
            }
            unchecked {
                i++;
            }
        }
    }
}
