// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {OrderFiller} from "../../lib/OrderFiller.sol";
import {OrderValidator} from "../../lib/OrderValidator.sol";
import {
    DutchLimitOrder,
    DutchLimitOrderExecution,
    DutchOutput
} from "./DutchLimitOrderStructs.sol";
import {
    ResolvedOrder,
    TokenAmount,
    OrderFill,
    Output
} from "../../interfaces/ReactorStructs.sol";

/// @notice Reactor for dutch limit orders
contract DutchLimitOrderReactor is OrderValidator {
    using OrderFiller for ResolvedOrder;

    address public immutable permitPost;

    error EndTimeBeforeStart();
    error DeadlineBeforeEndTime();

    constructor(address _permitPost) {
        permitPost = _permitPost;
    }

    function execute(DutchLimitOrderExecution calldata execution) external {
        validate(execution.order);
        ResolvedOrder memory order = resolve(execution.order);
        order.fill(
            OrderFill({
                offerer: execution.order.info.offerer,
                sig: execution.sig,
                permitPost: permitPost,
                // TODO: use eip 712 typed msg hashing
                orderHash: keccak256(abi.encode(execution.order)),
                fillContract: execution.fillContract,
                fillData: execution.fillData
            })
        );
    }

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

    function validate(DutchLimitOrder calldata dutchLimitOrder) public view {
        if (dutchLimitOrder.endTime <= dutchLimitOrder.startTime) {
            revert EndTimeBeforeStart();
        }
        if (dutchLimitOrder.info.deadline < dutchLimitOrder.endTime) {
            revert DeadlineBeforeEndTime();
        }
        validateOrderInfo(dutchLimitOrder.info);
    }
}
