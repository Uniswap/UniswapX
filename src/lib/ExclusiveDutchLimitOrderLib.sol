// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {OrderInfo} from "../base/ReactorStructs.sol";
import {DutchOutput, DutchInput, DutchLimitOrderLib} from "./DutchLimitOrderLib.sol";

struct ExclusiveDutchLimitOrder {
    // generic order information
    OrderInfo info;
    // The time at which the DutchOutputs start decaying
    uint256 startTime;
    // The time at which price becomes static
    uint256 endTime;
    // The address who has exclusive rights to the order until startTime
    address exclusiveFiller;
    // The tokens that the offerer will provide when settling the order
    DutchInput input;
    // The tokens that must be received to satisfy the order
    DutchOutput[] outputs;
}

/// @notice helpers for handling dutch limit order objects
library ExclusiveDutchLimitOrderLib {
    using DutchLimitOrderLib for DutchOutput[];

    bytes internal constant ORDER_TYPE = abi.encodePacked(
        "ExclusiveDutchLimitOrder(",
        "address reactor,",
        "address offerer,",
        "uint256 nonce,",
        "uint256 deadline,",
        "address validationContract,",
        "bytes validationData,",
        "uint256 startTime,",
        "uint256 endTime,",
        "address exclusiveFiller,",
        "address inputToken,",
        "uint256 inputStartAmount,",
        "uint256 inputEndAmount,",
        "DutchOutput[] outputs)",
        DutchLimitOrderLib.DUTCH_OUTPUT_TYPE
    );
    bytes32 internal constant ORDER_TYPE_HASH = keccak256(ORDER_TYPE);

    string internal constant PERMIT2_ORDER_TYPE = string(
        abi.encodePacked("ExclusiveDutchLimitOrder witness)", ORDER_TYPE, DutchLimitOrderLib.TOKEN_PERMISSIONS_TYPE)
    );

    /// @notice hash the given order
    /// @param order the order to hash
    /// @return the eip-712 order hash
    function hash(ExclusiveDutchLimitOrder memory order) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                ORDER_TYPE_HASH,
                order.info.reactor,
                order.info.offerer,
                order.info.nonce,
                order.info.deadline,
                order.info.validationContract,
                keccak256(order.info.validationData),
                order.startTime,
                order.endTime,
                order.exclusiveFiller,
                order.input.token,
                order.input.startAmount,
                order.input.endAmount,
                order.outputs.hash()
            )
        );
    }
}
