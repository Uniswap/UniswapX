// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {OrderFiller} from "../../lib/OrderFiller.sol";
import {OrderValidator} from "../../lib/OrderValidator.sol";
import {BaseReactor} from "../BaseReactor.sol";
import {
    DutchLimitOrder,
    DutchLimitOrderExecution,
    DutchOutput
} from "./DutchLimitOrderStructs.sol";
import {
    ResolvedOrder,
    TokenAmount,
    OrderInfo,
    OrderFill,
    Output
} from "../../interfaces/ReactorStructs.sol";

/// @notice Reactor for dutch limit orders
contract DutchLimitOrderReactor is BaseReactor {
    using OrderFiller for OrderFill;
    using OrderValidator for OrderInfo;

    error EndTimeBeforeStart();
    error DeadlineBeforeEndTime();

    constructor(address _permitPost) BaseReactor(_permitPost) {}

    /// @notice Execute the given order execution
    /// @dev Resolves the order inputs and outputs,
    ///     validates the order, and fills it if valid.
    ///     - User funds must be supplied through the permit post
    ///     and fetched through a valid permit signature
    ///     - Order execution through the fillContract must
    ///     properly return all user outputs
    function execute(DutchLimitOrderExecution calldata execution) external {
        _validateDutchOrder(execution.order);
        fill(
            OrderFill({
                order: resolve(execution.order),
                sig: execution.sig,
                permitPost: permitPost,
                orderHash: keccak256(abi.encode(execution.order)),
                fillContract: execution.fillContract,
                fillData: execution.fillData
            })
        );
    }

    /// @notice Resolve a DutchLimitOrder into a generic order
    /// @dev applies dutch decay to order outputs
    function resolve(DutchLimitOrder calldata dutchLimitOrder)
        public
        view
        returns (ResolvedOrder memory resolvedOrder)
    {
        Output[] memory outputs = new Output[](dutchLimitOrder.outputs.length);
        for (uint256 i = 0; i < outputs.length; i++) {
            DutchOutput calldata dutchOutput_i = dutchLimitOrder.outputs[i];
            uint256 decayedAmount;
            if (dutchLimitOrder.endTime < block.timestamp) {
                decayedAmount = dutchOutput_i.endAmount;
            } else {
                decayedAmount = dutchOutput_i.startAmount
                    - (dutchOutput_i.startAmount - dutchOutput_i.endAmount)
                        * (block.timestamp - dutchLimitOrder.startTime)
                        / (dutchLimitOrder.endTime - dutchLimitOrder.startTime);
            }
            outputs[i] =
                Output(dutchOutput_i.token, decayedAmount, dutchOutput_i.recipient);
        }
        resolvedOrder =
            ResolvedOrder(dutchLimitOrder.info, dutchLimitOrder.input, outputs);
    }

    /// @notice validate an order
    /// @dev Throws if the order is invalid
    function validate(DutchLimitOrder calldata order) external view {
        order.info.validate();
        _validateDutchOrder(order);
    }

    /// @notice validate the dutch order fields
    /// @dev Throws if the order is invalid
    function _validateDutchOrder(DutchLimitOrder calldata dutchLimitOrder)
        internal
        pure
    {
        if (dutchLimitOrder.endTime <= dutchLimitOrder.startTime) {
            revert EndTimeBeforeStart();
        }
        if (dutchLimitOrder.info.deadline < dutchLimitOrder.endTime) {
            revert DeadlineBeforeEndTime();
        }
    }
}
