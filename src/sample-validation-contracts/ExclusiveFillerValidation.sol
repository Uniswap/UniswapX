// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {IValidationCallback} from "../interfaces/IValidationCallback.sol";
import {ResolvedOrder, OrderInfo} from "../base/ReactorStructs.sol";

contract ExclusiveFillerValidation is IValidationCallback {
    error ValidationFailed();

    constructor() {}

    /// @notice Custom validation contract that gives exclusive filling rights for RFQ winners.
    /// @param filler The filler of the order
    /// @param resolvedOrder The resolved order to fill. Its `info.validationData` has the following 3 fields encoded:
    /// exclusiveFiller: The RFQ winner that has won exclusive rights to fill this order until `lastExclusiveTimestamp`
    /// lastExclusiveTimestamp: see above
    /// overrideIncreaseRequired: If non zero, non RFQ winners may fill this order prior to `lastExclusiveTimestamp` if
    /// they increase their output amounts by `outputIncrease` basis points. If zero, only RFQ winner may fill this order
    /// prior to `lastExclusiveTimestamp`
    /// @return outputIncrease the number of basis points that output amounts will increase by
    function validate(address filler, ResolvedOrder calldata resolvedOrder)
        external
        view
        returns (uint256 outputIncrease)
    {
        (address exclusiveFiller, uint256 lastExclusiveTimestamp, uint256 overrideIncreaseRequired) =
            abi.decode(resolvedOrder.info.validationData, (address, uint256, uint256));
        if (filler != exclusiveFiller && block.timestamp <= lastExclusiveTimestamp) {
            if (overrideIncreaseRequired == 0) {
                revert ValidationFailed();
            } else {
                outputIncrease = overrideIncreaseRequired;
            }
        }
    }
}
