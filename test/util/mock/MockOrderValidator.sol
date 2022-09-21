// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {OrderValidator} from "../../../src/base/OrderValidator.sol";
import {OrderInfo, OrderStatus} from "../../../src/base/ReactorStructs.sol";

contract MockOrderValidator is OrderValidator {
    function validate(OrderInfo memory info) external view {
        _validateOrderInfo(info);
    }

    function updateFilled(bytes32 orderHash) external {
        _updateFilled(orderHash);
    }

    function updateCancelled(bytes32 orderHash) external {
        _updateCancelled(orderHash);
    }

    function getOrderStatus(bytes32 orderHash) external view returns (OrderStatus memory status) {
        status = orderStatus[orderHash];
    }
}
