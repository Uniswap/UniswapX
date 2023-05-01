// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.19;

import {OrderInfo} from "../base/ReactorStructs.sol";
import {DutchOutput, DutchInput, DutchLimitOrderLib} from "./DutchLimitOrderLib.sol";
import {OrderInfoLib} from "./OrderInfoLib.sol";

struct ExclusiveDutchLimitOrder {
    // generic order information
    OrderInfo info;
    // The time at which the DutchOutputs start decaying
    uint256 startTime;
    // The time at which price becomes static
    uint256 endTime;
    // The address who has exclusive rights to the order until startTime
    address exclusiveFiller;
    // The amount in bps that a non-exclusive filler needs to improve the outputs by to be able to fill the order
    uint256 exclusivityOverrideBps;
    // The tokens that the offerer will provide when settling the order
    DutchInput input;
    // The tokens that must be received to satisfy the order
    DutchOutput[] outputs;
}

/// @notice helpers for handling dutch limit order objects
library ExclusiveDutchLimitOrderLib {
    using DutchLimitOrderLib for DutchOutput[];
    using OrderInfoLib for OrderInfo;

    bytes internal constant EXCLUSIVE_DUTCH_LIMIT_ORDER_TYPE = abi.encodePacked(
        "ExclusiveDutchLimitOrder(",
        "OrderInfo info,",
        "uint256 startTime,",
        "uint256 endTime,",
        "address exclusiveFiller,",
        "uint256 exclusivityOverrideBps,",
        "address inputToken,",
        "uint256 inputStartAmount,",
        "uint256 inputEndAmount,",
        "DutchOutput[] outputs)"
    );

    bytes internal constant ORDER_TYPE = abi.encodePacked(
        EXCLUSIVE_DUTCH_LIMIT_ORDER_TYPE, DutchLimitOrderLib.DUTCH_OUTPUT_TYPE, OrderInfoLib.ORDER_INFO_TYPE
    );
    bytes32 internal constant ORDER_TYPE_HASH = keccak256(ORDER_TYPE);

    /// @dev Note that sub-structs have to be defined in alphabetical order in the EIP-712 spec
    string internal constant PERMIT2_ORDER_TYPE = string(
        abi.encodePacked(
            "ExclusiveDutchLimitOrder witness)",
            DutchLimitOrderLib.DUTCH_OUTPUT_TYPE,
            EXCLUSIVE_DUTCH_LIMIT_ORDER_TYPE,
            OrderInfoLib.ORDER_INFO_TYPE,
            DutchLimitOrderLib.TOKEN_PERMISSIONS_TYPE
        )
    );

    /// @notice hash the given order
    /// @param order the order to hash
    /// @return the eip-712 order hash
    function hash(ExclusiveDutchLimitOrder memory order) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                ORDER_TYPE_HASH,
                order.info.hash(),
                order.startTime,
                order.endTime,
                order.exclusiveFiller,
                order.exclusivityOverrideBps,
                order.input.token,
                order.input.startAmount,
                order.input.endAmount,
                order.outputs.hash()
            )
        );
    }
}
