// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {ResolvedOrder} from "../base/SettlementStructs.sol";
import {OrderInfo} from "../../base/ReactorStructs.sol";
import {IValidationCallback} from "../interfaces/IValidationCallback.sol";

library ResolvedOrderLib {
    error InvalidReactor();
    error DeadlinePassed();
    error ValidationFailed();

    /// @notice Validates a resolved order, reverting if invalid
    /// @param filler The filler of the order
    function validate(ResolvedOrder memory resolvedOrder, address filler) internal view {
        if (address(this) != resolvedOrder.info.settlementOracle) {
            revert InvalidReactor();
        }

        if (block.timestamp > resolvedOrder.info.fillDeadline) {
            revert DeadlinePassed();
        }

        if (
            resolvedOrder.info.validationContract != address(0)
                && !IValidationCallback(resolvedOrder.info.validationContract).validate(filler, resolvedOrder)
        ) {
            revert ValidationFailed();
        }
    }
}
