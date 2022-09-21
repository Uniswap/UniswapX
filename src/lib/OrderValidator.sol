// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {OrderInfo} from "../lib/ReactorStructs.sol";

contract OrderValidator {
    error InvalidReactor();
    error DeadlinePassed();
    error OrderAlreadyFilled();

    mapping(bytes32 => bool) public isFilled;

    /// @notice Validates an order, reverting if invalid
    /// @param info The order to validate
    function _validateOrderInfo(OrderInfo memory info) internal view {
        if (address(this) != info.reactor) {
            revert InvalidReactor();
        }

        if (block.timestamp > info.deadline) {
            revert DeadlinePassed();
        }
    }

    /// @notice marks an order as filled
    function _updateFilled(bytes32 orderHash) internal {
        if (isFilled[orderHash]) {
            revert OrderAlreadyFilled();
        }

        isFilled[orderHash] = true;
    }
}
