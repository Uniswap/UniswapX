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
    error InputAndOutputDecay();

    constructor(address _permitPost) BaseReactor(_permitPost) {}

    /// @notice Resolve a DutchLimitOrder into a generic order
    /// @dev applies dutch decay to order outputs
    function resolve(bytes calldata order) public view override returns (ResolvedOrder memory resolvedOrder) {
        DutchLimitOrder memory dutchLimitOrder = abi.decode(order, (DutchLimitOrder));
        _validateOrder(dutchLimitOrder);

        Output[] memory outputs = new Output[](dutchLimitOrder.outputs.length);
        for (uint256 i = 0; i < outputs.length; i++) {
            DutchOutput memory output = dutchLimitOrder.outputs[i];
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
        resolvedOrder = ResolvedOrder(
            dutchLimitOrder.info, TokenAmount(dutchLimitOrder.input.token, dutchLimitOrder.input.startAmount), outputs
        );
    }

    /// @notice validate the dutch order fields
    /// endTime must be greater or equal than startTime
    /// deadline must be less than endTime
    /// if there's input decay, outputs must not decay
    /// @dev Throws if the order is invalid
    function _validateOrder(DutchLimitOrder memory dutchLimitOrder) internal pure {
        if (dutchLimitOrder.endTime <= dutchLimitOrder.startTime) {
            revert EndTimeBeforeStart();
        }

        if (dutchLimitOrder.info.deadline < dutchLimitOrder.endTime) {
            revert DeadlineBeforeEndTime();
        }

        if (dutchLimitOrder.input.startAmount != dutchLimitOrder.input.endAmount) {
            for (uint256 i = 0; i < dutchLimitOrder.outputs.length; i++) {
                if (dutchLimitOrder.outputs[i].startAmount != dutchLimitOrder.outputs[i].endAmount) {
                    revert InputAndOutputDecay();
                }
            }
        }
    }
}
