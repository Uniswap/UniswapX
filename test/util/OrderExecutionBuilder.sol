// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    Output,
    Order,
    OrderInfo,
    OrderExecution,
    Signature
} from "../../src/interfaces/ReactorStructs.sol";
import {OrderInfoBuilder} from "./OrderInfoBuilder.sol";

library OrderExecutionBuilder {
    using OrderInfoBuilder for OrderInfo;

    function init() internal view returns (OrderExecution memory) {
        return OrderExecution({
            order: Order({info: OrderInfoBuilder.init(), data: bytes("")}),
            fillContract: address(0),
            fillData: bytes(""),
            sig: Signature(0, 0, 0)
        });
    }

    function withReactor(OrderExecution memory execution, address _reactor)
        internal
        pure
        returns (OrderExecution memory)
    {
        execution.order.info = execution.order.info.withReactor(_reactor);
        return execution;
    }

    function withOfferer(OrderExecution memory execution, address _offerer)
        internal
        pure
        returns (OrderExecution memory)
    {
        execution.order.info = execution.order.info.withOfferer(_offerer);
        // TODO: update sig
        return execution;
    }

    function withData(OrderExecution memory execution, bytes memory _data)
        internal
        pure
        returns (OrderExecution memory)
    {
        execution.order.data = _data;
        return execution;
    }

    function withFillContract(
        OrderExecution memory execution,
        address _fillContract
    )
        internal
        pure
        returns (OrderExecution memory)
    {
        execution.fillContract = _fillContract;
        return execution;
    }

    function withFillData(
        OrderExecution memory execution,
        bytes memory _fillData
    )
        internal
        pure
        returns (OrderExecution memory)
    {
        execution.fillData = _fillData;
        return execution;
    }
}
