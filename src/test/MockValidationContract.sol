// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {OrderInfo} from "../interfaces/ReactorStructs.sol";
import {IValidationContract} from "../interfaces/IValidationContract.sol";

contract MockValidationContract {
    bool public valid;

    function setValid(bool _valid) external {
        valid = _valid;
    }

    function validate(OrderInfo memory) external view returns (bool) {
        return valid;
    }
}
