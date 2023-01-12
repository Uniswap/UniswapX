// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {ResolvedXOrder} from "../base/XReactorStructs.sol";
import {OrderInfo} from "../../base/ReactorStructs.sol";
import {IXValidationCallback} from "../interfaces/IXValidationCallback.sol";

library ResolvedXOrderLib {
    error InvalidReactor();
    error DeadlinePassed();
    error ValidationFailed();

    /// @notice Validates a resolved order, reverting if invalid
    /// @param filler The filler of the order
    function validate(ResolvedXOrder memory resolvedOrder, address filler) internal view {
        if (address(this) != resolvedOrder.info.reactor) {
            revert InvalidReactor();
        }

        if (block.timestamp > resolvedOrder.info.fillDeadline) {
            revert DeadlinePassed();
        }

        if (
            resolvedOrder.info.validationContract != address(0)
                && !IXValidationCallback(resolvedOrder.info.validationContract).validate(filler, resolvedOrder)
        ) {
            revert ValidationFailed();
        }
    }
}
