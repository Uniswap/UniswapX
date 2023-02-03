pragma solidity ^0.8.16;

import {IValidationCallback} from "../../../src/interfaces/IValidationCallback.sol";
import {OrderInfo, ResolvedOrder} from "../../../src/base/ReactorStructs.sol";

contract MockValidationContract is IValidationCallback {
    error ValidationFailed();

    bool public valid;

    function setValid(bool _valid) external {
        valid = _valid;
    }

    function validate(address, ResolvedOrder memory) external view returns (uint256) {
        if (valid) {
            return 0;
        } else {
            revert ValidationFailed();
        }
    }
}
