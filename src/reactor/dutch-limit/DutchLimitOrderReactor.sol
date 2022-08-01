// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {OrderFiller} from "../../lib/OrderFiller.sol";
import {OrderValidator} from "../../lib/OrderValidator.sol";
import {DutchLimitOrder, DutchLimitOrderExecution, DutchOutput} from "./DutchLimitOrderStructs.sol";
import {ResolvedOrder, TokenAmount, Output} from "../../interfaces/ReactorStructs.sol";

/// @notice Reactor for dutch limit orders
contract DutchLimitOrderReactor is OrderValidator {
    using OrderFiller for ResolvedOrder;

    error EndTimeBeforeStart();
    error DeadlineBeforeEndTime();

    function execute(DutchLimitOrderExecution calldata execution) external {
        validateDutchLimitOrder(execution.order);
        ResolvedOrder memory order = resolve(execution.order);
        order.fill(
            execution.order.info.offerer,
            execution.sig,
            execution.fillContract,
            execution.fillData
        );
    }

    function resolve(DutchLimitOrder calldata dutchLimitOrder) public view returns (ResolvedOrder memory resolvedOrder) {
        Output[] memory outputs = new Output[](dutchLimitOrder.outputs.length);
        for (uint i = 0; i < outputs.length; i++) {
            DutchOutput calldata dutchOutput_i =  dutchLimitOrder.outputs[i];
            uint decayedAmount;
            if (dutchLimitOrder.endTime < block.timestamp) {
                decayedAmount = dutchOutput_i.endAmount;
            } else {
                decayedAmount =
                    dutchOutput_i.startAmount
                    - (dutchOutput_i.startAmount - dutchOutput_i.endAmount)
                    * (block.timestamp - dutchLimitOrder.startTime)
                    / (dutchLimitOrder.endTime - dutchLimitOrder.startTime);
            }
            outputs[i] = Output(
                dutchOutput_i.token,
                decayedAmount,
                dutchOutput_i.recipient
            );
        }
        resolvedOrder = ResolvedOrder(dutchLimitOrder.input, outputs);
    }

    function validateDutchLimitOrder(DutchLimitOrder calldata dutchLimitOrder) public view {
        if (dutchLimitOrder.endTime <= dutchLimitOrder.startTime) {
            revert EndTimeBeforeStart();
        }
        if (dutchLimitOrder.info.deadline < dutchLimitOrder.endTime) {
            revert DeadlineBeforeEndTime();
        }
        validateOrder(dutchLimitOrder.info);
    }
}
