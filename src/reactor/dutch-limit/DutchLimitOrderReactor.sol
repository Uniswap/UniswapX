// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {OrderFiller} from "../../lib/OrderFiller.sol";
import {OrderValidator} from "../../lib/OrderValidator.sol";
import {DutchLimitOrder, DutchLimitOrderExecution} from "./DutchLimitOrderStructs.sol";
import {ResolvedOrder, TokenAmount, Output} from "../../interfaces/ReactorStructs.sol";

/// @notice Reactor for dutch limit orders
contract DutchLimitOrderReactor is OrderValidator {
    using OrderFiller for ResolvedOrder;

    function execute(DutchLimitOrderExecution calldata execution) external {
        validateOrder(execution.order.info);
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
            uint decayedAmount =
                dutchLimitOrder.outputs[i].startAmount
                - (dutchLimitOrder.outputs[i].startAmount - dutchLimitOrder.outputs[i].endAmount)
                * (block.timestamp - dutchLimitOrder.startTime)
                / (dutchLimitOrder.endTime - dutchLimitOrder.startTime);
            outputs[i] = Output(
                dutchLimitOrder.outputs[i].token,
                decayedAmount,
                dutchLimitOrder.outputs[i].recipient
            );
        }
        resolvedOrder = ResolvedOrder(dutchLimitOrder.input, outputs);
    }
}
