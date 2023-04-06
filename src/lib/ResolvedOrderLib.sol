// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {ResolvedOrder, OrderInfo} from "../base/ReactorStructs.sol";
import {IValidationCallback} from "../interfaces/IValidationCallback.sol";

library ResolvedOrderLib {
    error InvalidReactor();
    error DeadlinePassed();
    error ValidationFailed();

    /// @notice Validates a resolved order, reverting if invalid
    /// @param filler The filler of the order
    function validate(ResolvedOrder memory resolvedOrder, address filler) internal view {
        OrderInfo memory orderInfo = resolvedOrder.info;
        if (address(this) != orderInfo.reactor) {
            revert InvalidReactor();
        }

        if (block.timestamp > orderInfo.deadline) {
            revert DeadlinePassed();
        }

        if (
            orderInfo.validationContract != address(0)
                && !IValidationCallback(orderInfo.validationContract).validate(filler, resolvedOrder)
        ) {
            revert ValidationFailed();
        }
    }
}
