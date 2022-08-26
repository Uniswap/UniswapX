// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {OrderValidator} from "../../lib/OrderValidator.sol";
import {BaseReactor} from "../BaseReactor.sol";
import {LimitOrder, LimitOrderExecution} from "./LimitOrderStructs.sol";
import {
    ResolvedOrder,
    OrderInfo,
    TokenAmount
} from "../../interfaces/ReactorStructs.sol";

/// @notice Reactor for simple limit orders
contract LimitOrderReactor is BaseReactor {
    using OrderValidator for OrderInfo;

    constructor(address _permitPost) BaseReactor(_permitPost) {}

    /// @notice Execute the given order execution
    /// @dev Resolves the order inputs and outputs,
    ///     validates the order, and fills it if valid.
    ///     - User funds must be supplied through the permit post
    ///     and fetched through a valid permit signature
    ///     - Order execution through the fillContract must
    ///     properly return all user outputs
    function execute(LimitOrderExecution calldata execution) external {
        fill(
            resolve(execution.order),
            execution.sig,
            keccak256(abi.encode(execution.order)),
            execution.fillContract,
            execution.fillData
        );
    }

    /// @notice Resolve a LimitOrder into a generic order
    /// @dev limit order inputs and outputs are directly specified
    function resolve(LimitOrder calldata order)
        public
        pure
        returns (ResolvedOrder memory resolvedOrder)
    {
        resolvedOrder = ResolvedOrder(order.info, order.input, order.outputs);
    }

    /// @notice validate an order
    /// @dev Throws if the order is invalid
    function validate(LimitOrder calldata order) external view {
        order.info.validate();
    }
}
