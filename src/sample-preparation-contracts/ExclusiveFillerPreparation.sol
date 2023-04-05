// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {IOrderPreparation} from "../interfaces/IOrderPreparation.sol";
import {ResolvedOrder, OrderInfo} from "../base/ReactorStructs.sol";

contract ExclusiveFillerPreparation is IOrderPreparation {
    error ValidationFailed();

    constructor() {}

    /// @notice Custom validation contract that gives exclusive filling rights for RFQ winners.
    /// @param filler The filler of the order
    /// @param resolvedOrder The resolved order to fill. Its `info.preparationData` has the following 3 fields encoded:
    /// exclusiveFiller: The RFQ winner that has won exclusive rights to fill this order until `lastExclusiveTimestamp`
    /// lastExclusiveTimestamp: see above
    /// overrideIncreaseRequired: If non zero, non RFQ winners may fill this order prior to `lastExclusiveTimestamp` if
    /// they increase their output amounts by `outputIncrease` basis points. If zero, only RFQ winner may fill this order
    /// prior to `lastExclusiveTimestamp`
    /// @return updatedOrder
    function prepare(address filler, ResolvedOrder calldata resolvedOrder)
        external
        view
        returns (ResolvedOrder memory updatedOrder)
    {
        updatedOrder = resolvedOrder;
        (address exclusiveFiller, uint256 lastExclusiveTimestamp, uint256 overrideIncreaseRequired) =
            abi.decode(resolvedOrder.info.preparationData, (address, uint256, uint256));

        if (filler != exclusiveFiller && block.timestamp <= lastExclusiveTimestamp) {
            if (overrideIncreaseRequired == 0) {
                revert ValidationFailed();
            } else {
                for (uint256 i = 0; i < updatedOrder.outputs.length; i++) {
                    updatedOrder.outputs[i].amount =
                        (updatedOrder.outputs[i].amount * (10000 + overrideIncreaseRequired)) /
                        10000;
                }
            }
        }
    }
}
