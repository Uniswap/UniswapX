// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {OrderValidator} from "../lib/OrderValidator.sol";
import {OrderInfo, OrderStatus} from "../interfaces/ReactorStructs.sol";
import {IValidationCallback} from "../interfaces/IValidationCallback.sol";

contract MockOrderValidator {
    using OrderValidator for OrderInfo;
    using OrderValidator for mapping(bytes32 => OrderStatus);

    mapping(bytes32 => OrderStatus) public orderStatus;

    function validate(OrderInfo memory info) external view {
        info.validate();
    }

    function updateFilled(bytes32 orderHash) external {
        orderStatus.updateFilled(orderHash);
    }

    function updateCancelled(bytes32 orderHash) external {
        orderStatus.updateCancelled(orderHash);
    }

    function getOrderStatus(bytes32 orderHash)
        external
        returns (OrderStatus memory)
    {
        return orderStatus[orderHash];
    }
}
