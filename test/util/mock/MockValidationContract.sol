pragma solidity ^0.8.16;

import {IValidationCallback} from "../../../src/interfaces/IValidationCallback.sol";
import {OrderInfo, ResolvedOrder} from "../../../src/base/ReactorStructs.sol";

contract MockValidationContract is IValidationCallback {
    bool public valid;

    function setValid(bool _valid) external {
        valid = _valid;
    }

    function validate(address filler, ResolvedOrder memory resolvedOrder)
        external
        view
        returns (bool)
    {
        return valid;
    }
}
