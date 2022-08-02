// SPDX-License-Identifier: GPL-2.0dor-later
pragma solidity ^0.8.0;

import {OrderInfo} from "../interfaces/ReactorStructs.sol";
import {IValidationCallback} from "../interfaces/IValidationCallback.sol";

contract MockValidationContract is IValidationCallback {
    bool public valid;

    function setValid(bool _valid) external {
        valid = _valid;
    }

    function validate(OrderInfo memory) external view returns (bool) {
        return valid;
    }
}
