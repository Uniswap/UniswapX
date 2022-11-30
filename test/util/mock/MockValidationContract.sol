pragma solidity ^0.8.16;

import {IValidationCallback} from "../../../src/interfaces/IValidationCallback.sol";
import {OrderInfo} from "../../../src/base/ReactorStructs.sol";

contract MockValidationContract is IValidationCallback {
    bool public valid;

    function setValid(bool _valid) external {
        valid = _valid;
    }

    function validate(OrderInfo memory) external view returns (bool) {
        return valid;
    }
}
