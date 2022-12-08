// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {IValidationCallback} from "../interfaces/IValidationCallback.sol";
import {ResolvedOrder, OrderInfo} from "../base/ReactorStructs.sol";

contract RfqValidationContract is IValidationCallback {

    constructor() {}

    function validate(OrderInfo memory order, address filler, ResolvedOrder calldata resolvedOrder)
        external
        view
        returns (bool)
    {

    }
}
