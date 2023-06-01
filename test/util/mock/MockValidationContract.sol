// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IValidationCallback} from "../../../src/interfaces/IValidationCallback.sol";
import {OrderInfo, ResolvedOrder} from "../../../src/base/ReactorStructs.sol";

contract MockValidationContract is IValidationCallback {
    error MockValidationError();

    bool public valid;

    function setValid(bool _valid) external {
        valid = _valid;
    }

    function validate(address, ResolvedOrder memory) external view {
        if (!valid) {
            revert MockValidationError();
        }
    }
}
