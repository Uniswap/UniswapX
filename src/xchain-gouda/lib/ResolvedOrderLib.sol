// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {ResolvedOrder} from "../base/SettlementStructs.sol";
import {OrderInfo} from "../../base/ReactorStructs.sol";
import {IValidationCallback} from "../interfaces/IValidationCallback.sol";
import {console} from "forge-std/console.sol";


library ResolvedOrderLib {
    error InvalidSettler();
    error InitiateDeadlinePassed();
    error ValidationFailed();

    /// @notice Validates a resolved order, reverting if invalid
    /// @param originChainFiller The filler that initiated the settlement on the origin chain
    function validate(ResolvedOrder memory resolvedOrder, address originChainFiller) internal view {
        console.log('here');
        if (address(this) != resolvedOrder.info.settlerContract) revert InvalidSettler();
        if (block.timestamp > resolvedOrder.info.initiateDeadline) revert InitiateDeadlinePassed();

        if (resolvedOrder.info.validationContract != address(0)) {
            if (!IValidationCallback(resolvedOrder.info.validationContract).validate(originChainFiller, resolvedOrder))
            {
                revert ValidationFailed();
            }
        }
    }
}
