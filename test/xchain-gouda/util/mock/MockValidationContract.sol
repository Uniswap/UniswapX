pragma solidity ^0.8.16;

import {IValidationCallback} from "../../../../src/xchain-gouda/interfaces/IValidationCallback.sol";
import {ResolvedOrder} from "../../../../src/xchain-gouda/base/SettlementStructs.sol";

contract MockValidationContract is IValidationCallback {
    bool public valid;

    function setValid(bool _valid) external {
        valid = _valid;
    }

    function validate(address, ResolvedOrder memory) external view returns (bool) {
        return valid;
    }
}
