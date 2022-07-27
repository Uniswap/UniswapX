// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "solmate/tokens/ERC20.sol";
import {
    TokenAmount,
    OrderExecution,
    Order,
    Output,
    ResolvedOrder,
    Signature
} from "../interfaces/ReactorStructs.sol";
import {OrderValidator} from "../lib/OrderValidator.sol";
import {IReactorCallback} from "../interfaces/IReactorCallback.sol";
import {IReactor} from "../interfaces/IReactor.sol";

abstract contract BaseReactor is IReactor, OrderValidator {
    /// @inheritdoc IReactor
    function execute(OrderExecution calldata execution) external override {
        validateOrder(execution.order.info);
        ResolvedOrder memory order = _resolve(execution.order);
        _fill(
            order,
            execution.order.info.offerer,
            execution.sig,
            execution.fillContract,
            execution.fillData
        );
    }

    /// @notice fill an order
    function _fill(
        ResolvedOrder memory order,
        address offerer,
        Signature memory,
        address fillContract,
        bytes memory fillData
    )
        internal
        virtual
    {
        // TODO: use permit post instead to send input tokens to fill contract
        // transfer input tokens to the fill contract
        ERC20(order.input.token).transferFrom(
            offerer, fillContract, order.input.amount
        );

        IReactorCallback(fillContract).reactorCallback(order.outputs, fillData);

        // transfer output tokens to their respective recipients
        for (uint256 i = 0; i < order.outputs.length; i++) {
            Output memory output = order.outputs[i];
            ERC20(output.token).transferFrom(
                fillContract, output.recipient, output.amount
            );
        }
    }

    /// @notice resolve an order's inputs and outputs
    /// @param order The order to resolve
    /// @return The real inputs and outputs after resolution
    function _resolve(Order calldata order)
        internal
        pure
        virtual
        returns (ResolvedOrder memory);
}
