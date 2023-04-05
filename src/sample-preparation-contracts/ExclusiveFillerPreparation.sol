// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {IOrderPreparation} from "../interfaces/IOrderPreparation.sol";
import {ResolvedOrder, OrderInfo} from "../base/ReactorStructs.sol";

contract ExclusiveFillerPreparation is IOrderPreparation {
    error ValidationFailed();

    uint256 private constant BPS = 10_000;

    constructor() {}

    /// @notice Custom validation contract that gives exclusive filling rights for RFQ winners.
    /// @param resolvedOrder The resolved order to fill. Its `info.preparationData` has the following 3 fields encoded:
    /// exclusiveFiller: The RFQ winner that has won exclusive rights to fill this order until `lastExclusiveTimestamp`
    /// lastExclusiveTimestamp: see above
    /// overrideIncreaseRequired: If non zero, non RFQ winners may fill this order prior to `lastExclusiveTimestamp` if
    /// they increase their output amounts by `outputIncrease` basis points. If zero, only RFQ winner may fill this order
    /// prior to `lastExclusiveTimestamp`
    /// @param filler The filler of the order
    /// @return preparedOrder The prepared order, including output override if necessary
    function prepare(ResolvedOrder calldata resolvedOrder, address filler)
        external
        view
        returns (ResolvedOrder memory preparedOrder)
    {
        preparedOrder = resolvedOrder;
        (address exclusiveFiller, uint256 lastExclusiveTimestamp, uint256 overrideIncreaseRequired) =
            abi.decode(resolvedOrder.info.preparationData, (address, uint256, uint256));

        if (filler != exclusiveFiller && block.timestamp <= lastExclusiveTimestamp) {
            if (overrideIncreaseRequired == 0 || overrideIncreaseRequired > BPS) {
                revert ValidationFailed();
            } else {
                for (uint256 i = 0; i < preparedOrder.outputs.length;) {
                    preparedOrder.outputs[i].amount =
                        (preparedOrder.outputs[i].amount * (BPS + overrideIncreaseRequired)) / BPS;

                    unchecked {
                        i++;
                    }
                }
            }
        }
    }
}
