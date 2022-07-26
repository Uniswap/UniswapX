// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    TokenAmount,
    OrderExecution,
    Order,
    ResolvedOrder,
    Signature
} from "../interfaces/ReactorStructs.sol";
import {OrderValidator} from "../lib/OrderValidator.sol";
import {IReactorCallback} from "../interfaces/IReactorCallback.sol";
import {IReactor} from "../interfaces/IReactor.sol";

abstract contract BaseReactor is IReactor, OrderValidator {
    function execute(OrderExecution calldata execution) external override {
        validateOrder(execution.order.info);
        ResolvedOrder memory order = resolve(execution.order);
        execute(
            order, execution.sig, execution.fillContract, execution.fillData
        );
    }

    /// @notice resolve an order's inputs and outputs
    /// @param order The order to resolve
    /// @return The real inputs and outputs after resolution
    function resolve(Order calldata order)
        internal
        virtual
        returns (ResolvedOrder memory);

    /// @notice execute an order
    function execute(
        ResolvedOrder memory order,
        Signature memory,
        address fillContract,
        bytes memory fillData
    )
        internal
        virtual {
            IReactorCallback(fillContract).reactorCallback(order.outputs, fillData);
        }
}
