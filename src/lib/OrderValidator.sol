// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    OrderStatus, OrderFill, OrderInfo
} from "../interfaces/ReactorStructs.sol";
import {IValidationCallback} from "../interfaces/IValidationCallback.sol";

library OrderValidator {
    error InvalidReactor();
    error DeadlinePassed();
    error InvalidOrder();
    error OrderCancelled();
    error OrderAlreadyFilled();

    /// @notice Validates an order, reverting if invalid
    /// @param order The order to validate
    function validate(OrderInfo memory order) internal view {
        if (address(this) != order.reactor) {
            revert InvalidReactor();
        }

        if (block.timestamp > order.deadline) {
            revert DeadlinePassed();
        }

        if (
            order.validationContract != address(0)
                && !IValidationCallback(order.validationContract).validate(order)
        ) {
            revert InvalidOrder();
        }
    }

    /// @notice marks an order as filled
    function updateFilled(
        mapping(bytes32 => OrderStatus) storage orderStatus,
        bytes32 orderHash
    )
        internal
    {
        OrderStatus memory _orderStatus = orderStatus[orderHash];
        if (_orderStatus.isCancelled) {
            revert OrderCancelled();
        }

        if (_orderStatus.isFilled) {
            revert OrderAlreadyFilled();
        }

        orderStatus[orderHash].isFilled = true;
    }

    /// @notice marks an order as canceled
    function updateCancelled(
        mapping(bytes32 => OrderStatus) storage orderStatus,
        bytes32 orderHash
    )
        internal
    {
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
