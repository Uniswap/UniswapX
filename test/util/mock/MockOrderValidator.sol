// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {OrderValidator} from "../../../src/lib/OrderValidator.sol";
import {OrderInfo} from "../../../src/lib/ReactorStructs.sol";

contract MockOrderValidator is OrderValidator {
    function validate(OrderInfo memory info) external view {
        _validate(info);
    }
}
