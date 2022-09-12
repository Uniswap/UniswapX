// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {OrderStatus, OrderInfo} from "../lib/ReactorStructs.sol";

contract OrderValidator {
    error InvalidReactor();
    error DeadlinePassed();

    /// @notice Validates an order, reverting if invalid
    /// @param info The order to validate
    function _validate(OrderInfo memory info) internal view {
        if (address(this) != info.reactor) {
            revert InvalidReactor();
        }

        if (block.timestamp > info.deadline) {
            revert DeadlinePassed();
        }
    }
}
