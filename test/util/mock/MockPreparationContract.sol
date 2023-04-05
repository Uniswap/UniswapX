// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {IOrderPreparation} from "../../../src/interfaces/IOrderPreparation.sol";
import {OrderInfo, ResolvedOrder} from "../../../src/base/ReactorStructs.sol";

contract MockPreparationContract is IOrderPreparation {
    error ValidationFailed();

    bool public valid;

    function setValid(bool _valid) external {
        valid = _valid;
    }

    function prepare(address, ResolvedOrder memory order) external view returns (ResolvedOrder memory) {
        if (valid) {
            return order;
        } else {
            revert ValidationFailed();
        }
    }
}
