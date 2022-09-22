// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {OrderInfo} from "../base/ReactorStructs.sol";

library OrderInfoLib {
    error InvalidReactor();
    error DeadlinePassed();

    /// @notice Validates an order, reverting if invalid
    /// @param info The order to validate
    function validate(OrderInfo memory info) internal view {
        if (address(this) != info.reactor) {
            revert InvalidReactor();
        }

        if (block.timestamp > info.deadline) {
            revert DeadlinePassed();
        }
    }
}
