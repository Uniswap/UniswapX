// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IValidationCallback} from "../interfaces/IValidationCallback.sol";
import {ResolvedOrder, OrderInfo} from "../base/ReactorStructs.sol";

contract ExclusiveFillerValidation is IValidationCallback {
    error NotExclusiveFiller();

    function validate(address filler, ResolvedOrder calldata resolvedOrder) external view {
        (address exclusiveFiller, uint256 lastExclusiveTimestamp) =
            abi.decode(resolvedOrder.info.additionalValidationData, (address, uint256));
        if (lastExclusiveTimestamp >= block.timestamp && filler != exclusiveFiller) {
            revert NotExclusiveFiller();
        }
    }
}
