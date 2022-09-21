// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {BaseReactor} from "../BaseReactor.sol";
import {DutchLimitOrder, DutchOutput} from "./DutchLimitOrderStructs.sol";
import {ResolvedOrder, OrderInfo, OutputToken, Signature} from "../../lib/ReactorStructs.sol";

/// @notice Reactor for dutch limit orders
contract DutchLimitOrderReactor is BaseReactor {
    using FixedPointMathLib for uint256;

    error EndTimeBeforeStart();
    error DeadlineBeforeEndTime();

    constructor(address _permitPost) BaseReactor(_permitPost) {}

    /// @notice Resolve a DutchLimitOrder into a generic order
    /// @dev applies dutch decay to order outputs
    function resolve(bytes memory order) internal view virtual override returns (ResolvedOrder memory resolvedOrder) {
        DutchLimitOrder memory dutchLimitOrder = abi.decode(order, (DutchLimitOrder));
        _validateOrder(dutchLimitOrder);

        OutputToken[] memory outputs = new OutputToken[](dutchLimitOrder.outputs.length);
        for (uint256 i = 0; i < outputs.length; i++) {
            DutchOutput memory output = dutchLimitOrder.outputs[i];
            uint256 decayedAmount;

            if (dutchLimitOrder.info.deadline <= block.timestamp || output.startAmount == output.endAmount) {
                decayedAmount = output.endAmount;
            } else if (dutchLimitOrder.startTime >= block.timestamp) {
                decayedAmount = output.startAmount;
            } else {
                // TODO: maybe handle case where startAmount < endAmount
                // i.e. for exactOutput case
                uint256 elapsed = block.timestamp - dutchLimitOrder.startTime;
                uint256 duration = dutchLimitOrder.info.deadline - dutchLimitOrder.startTime;
                uint256 decayAmount = output.startAmount - output.endAmount;
                decayedAmount = output.startAmount - decayAmount.mulDivDown(elapsed, duration);
            }
            outputs[i] = OutputToken(output.token, decayedAmount, output.recipient);
        }
        resolvedOrder = ResolvedOrder({
            info: dutchLimitOrder.info, 
            input: dutchLimitOrder.input, 
            outputs: outputs
        });
    }

    /// @notice validate the dutch order fields
    /// @dev Throws if the order is invalid
    function _validateOrder(DutchLimitOrder memory dutchLimitOrder) internal pure {
        if (dutchLimitOrder.info.deadline <= dutchLimitOrder.startTime) {
            revert EndTimeBeforeStart();
        }

        if (dutchLimitOrder.info.deadline < dutchLimitOrder.info.deadline) {
            revert DeadlineBeforeEndTime();
        }
    }
}
