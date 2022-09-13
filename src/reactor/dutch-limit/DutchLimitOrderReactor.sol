// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {BaseReactor} from "../BaseReactor.sol";
import {DutchLimitOrder, DutchOutput} from "./DutchLimitOrderStructs.sol";
import {ResolvedOrder, TokenAmount, OrderInfo, Output, Signature} from "../../lib/ReactorStructs.sol";

/// @notice Reactor for dutch limit orders
contract DutchLimitOrderReactor is BaseReactor {
    using FixedPointMathLib for uint256;

    error EndTimeBeforeStart();
    error DeadlineBeforeEndTime();
    error NotStarted();

    constructor(address _permitPost) BaseReactor(_permitPost) {}

    /// @notice Execute the given order execution
    /// @dev Resolves the order inputs and outputs,
    ///     validates the order, and fills it if valid.
    ///     - User funds must be supplied through the permit post
    ///     and fetched through a valid permit signature
    ///     - Order execution through the fillContract must
    ///     properly return all user outputs
    function execute(
        DutchLimitOrder calldata order,
        Signature calldata sig,
        address fillContract,
        bytes calldata fillData
    )
        external
    {
        _validateDutchOrder(order);
        _fill(resolve(order), sig, keccak256(abi.encode(order)), fillContract, fillData);
    }

    /// @notice Execute given orders
    function executeBatch(
        DutchLimitOrder[] calldata orders,
        Signature[] calldata signatures,
        address fillContract,
        bytes calldata fillData
    )
        external
    {
        ResolvedOrder[] memory resolvedOrders = new ResolvedOrder[](orders.length);
        bytes32[] memory orderHashes = new bytes32[](orders.length);
        for (uint256 i = 0; i < orders.length; i++) {
            _validateDutchOrder(orders[i]);
            resolvedOrders[i] = resolve(orders[i]);
            orderHashes[i] = keccak256(abi.encode(orders[i]));
        }
        _fillBatch(resolvedOrders, signatures, orderHashes, fillContract, fillData);
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
            DutchOutput calldata output = dutchLimitOrder.outputs[i];
            uint256 decayedAmount;

            if (dutchLimitOrder.endTime <= block.timestamp || output.startAmount == output.endAmount) {
                decayedAmount = output.endAmount;
            } else if (dutchLimitOrder.startTime >= block.timestamp) {
                decayedAmount = output.startAmount;
            } else {
                // TODO: maybe handle case where startAmount < endAmount
                // i.e. for exactOutput case
                uint256 elapsed = block.timestamp - dutchLimitOrder.startTime;
                uint256 duration = dutchLimitOrder.endTime - dutchLimitOrder.startTime;
                uint256 decayAmount = output.startAmount - output.endAmount;
                decayedAmount = output.startAmount - decayAmount.mulDivDown(elapsed, duration);
            }
            outputs[i] = Output(output.token, decayedAmount, output.recipient);
        }
        resolvedOrder = ResolvedOrder(dutchLimitOrder.info, dutchLimitOrder.input, outputs);
    }

    /// @notice validate an order
    /// @dev Throws if the order is invalid
    function validate(DutchLimitOrder calldata order) external view {
        _validate(order.info);
        _validateDutchOrder(order);
    }

    /// @notice validate the dutch order fields
    /// @dev Throws if the order is invalid
    function _validateDutchOrder(DutchLimitOrder calldata dutchLimitOrder) internal pure {
        if (dutchLimitOrder.endTime <= dutchLimitOrder.startTime) {
            revert EndTimeBeforeStart();
        }

        if (dutchLimitOrder.info.deadline < dutchLimitOrder.endTime) {
            revert DeadlineBeforeEndTime();
        }
    }
}
