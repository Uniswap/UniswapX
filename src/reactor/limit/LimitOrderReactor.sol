// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {OrderFiller} from "../../lib/OrderFiller.sol";
import {OrderValidator} from "../../lib/OrderValidator.sol";
import {LimitOrder, LimitOrderExecution} from "./LimitOrderStructs.sol";
import {
    ResolvedOrder,
    OrderFill,
    TokenAmount
} from "../../interfaces/ReactorStructs.sol";

/// @notice Reactor for simple limit orders
contract LimitOrderReactor is OrderValidator {
    using OrderFiller for ResolvedOrder;

    address public immutable permitPost;

    constructor(address _permitPost) {
        permitPost = _permitPost;
    }

    function execute(LimitOrderExecution calldata execution) external {
        validate(execution.order);
        resolve(execution.order).fill(
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

    function resolve(LimitOrder calldata order)
        public
        pure
        returns (ResolvedOrder memory resolvedOrder)
    {
        resolvedOrder = ResolvedOrder(order.info, order.input, order.outputs);
    }

    function validate(LimitOrder calldata order) public view {
        validateOrderInfo(order.info);
    }
}
