// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {ResolvedOrder} from "../base/SettlementStructs.sol";
import {OrderInfo} from "../../base/ReactorStructs.sol";
import {IValidationCallback} from "../interfaces/IValidationCallback.sol";

library ResolvedOrderLib {
    error InvalidReactor();
    error InitiateDeadlinePassed();
    error ValidationFailed();

    /// @notice Validates a resolved order, reverting if invalid
    /// @param originChainFiller The filler that initiated the settlement on the origin chain
    function validate(ResolvedOrder memory resolvedOrder, address originChainFiller) internal view {
        if (address(this) != resolvedOrder.info.settlerContract) revert InvalidReactor();
        if (block.timestamp > resolvedOrder.info.initiateDeadline) revert InitiateDeadlinePassed();

        if (resolvedOrder.info.validationContract != address(0)) {
            if (!IValidationCallback(resolvedOrder.info.validationContract).validate(originChainFiller, resolvedOrder))
            {
                revert ValidationFailed();
            }
        }
    }
}
