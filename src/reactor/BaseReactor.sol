// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {OrderFiller} from "../lib/OrderFiller.sol";
import {OrderValidator} from "../lib/OrderValidator.sol";
import {
    ResolvedOrder,
    OrderFill,
    OrderInfo,
    OrderStatus,
    TokenAmount,
    Signature
} from "../interfaces/ReactorStructs.sol";

/// @notice Reactor for simple limit orders
contract BaseReactor {
    using OrderFiller for OrderFill;
    using OrderValidator for mapping(bytes32 => OrderStatus);
    using OrderValidator for OrderInfo;

    address public immutable permitPost;

    mapping(bytes32 => OrderStatus) public orderStatus;

    constructor(address _permitPost) {
        permitPost = _permitPost;
    }

    /// @notice validates and fills an order, marking it as filled
    function fill(OrderFill memory orderFill) internal {
        orderFill.order.info.validate();
        orderStatus.updateFilled(orderFill.orderHash);
        orderFill.fill();
    }

    function fillBatch(
        ResolvedOrder[] memory orders,
        Signature[] memory signatures,
        bytes32[] memory orderHashes,
        address fillContract,
        bytes calldata fillData
    ) internal {

    }
}
