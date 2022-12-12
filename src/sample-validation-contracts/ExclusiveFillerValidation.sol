// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {IValidationCallback} from "../interfaces/IValidationCallback.sol";
import {ResolvedOrder, OrderInfo} from "../base/ReactorStructs.sol";

contract ExclusiveFillerValidation is IValidationCallback {
    constructor() {}

    function validate(OrderInfo memory order, address filler, ResolvedOrder calldata resolvedOrder)
        external
        view
        returns (bool)
    {
        (address exclusiveFiller, uint256 lastExclusiveTimestamp) = abi.decode(order.validationData, (address, uint256));
        return lastExclusiveTimestamp < block.timestamp || filler == exclusiveFiller;
    }
}
