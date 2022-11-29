// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {OrderInfo} from "../base/ReactorStructs.sol";
import {IValidationCallback} from "../interfaces/IValidationCallback.sol";
import "forge-std/console.sol";

library OrderInfoLib {
    error InvalidReactor();
    error DeadlinePassed();
    error InvalidOrder();

    /// @notice Validates an order, reverting if invalid
    /// @param info The order to validate
    function validate(OrderInfo memory info) internal view {
        console.log("entering validate");
        if (address(this) != info.reactor) {
            revert InvalidReactor();
        }

        if (block.timestamp > info.deadline) {
            revert DeadlinePassed();
        }

        console.log("info.validationContract", info.validationContract);
        console.log(
            "IValidationCallback(info.validationContract).validate(info)",
            IValidationCallback(info.validationContract).validate(info)
        );

        if (info.validationContract != address(0) && !IValidationCallback(info.validationContract).validate(info)) {
            console.log("prior to revert InvalidOrder");
            revert InvalidOrder();
        }
    }
}
