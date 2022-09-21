// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {OrderStatus, OrderInfo} from "../lib/ReactorStructs.sol";

contract OrderValidator {
    error InvalidReactor();
    error DeadlinePassed();
    error OrderCancelled();
    error OrderAlreadyFilled();

    mapping(bytes32 => OrderStatus) public orderStatus;

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
        OrderStatus memory _orderStatus = orderStatus[orderHash];
        if (_orderStatus.isCancelled) {
            revert OrderCancelled();
        }

        if (_orderStatus.isFilled) {
            revert OrderAlreadyFilled();
        }

        orderStatus[orderHash].isFilled = true;
    }

    /// @notice marks an order as cancelled
    function _updateCancelled(bytes32 orderHash) internal {
        OrderStatus memory _orderStatus = orderStatus[orderHash];
        if (_orderStatus.isCancelled) {
            revert OrderCancelled();
        }

        if (_orderStatus.isFilled) {
            revert OrderAlreadyFilled();
        }

        orderStatus[orderHash].isCancelled = true;
    }
}
