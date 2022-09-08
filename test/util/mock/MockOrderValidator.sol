// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {OrderValidator} from "../../../src/lib/OrderValidator.sol";
import {OrderInfo, OrderStatus} from "../../../src/lib/ReactorStructs.sol";

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
