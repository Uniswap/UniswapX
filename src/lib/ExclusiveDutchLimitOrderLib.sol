// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.19;

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
        "uint256 exclusivityOverrideBps,",
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
        OrderInfo memory info = order.info;
        DutchInput memory input = order.input;
        return keccak256(
            bytes.concat(
                // embedded encode avoids stack too deep
                abi.encode(
                    ORDER_TYPE_HASH,
                    info.reactor,
                    info.offerer,
                    info.nonce,
                    info.deadline,
                    info.validationContract,
                    keccak256(info.validationData)
                ),
                abi.encode(
                    order.startTime,
                    order.endTime,
                    order.exclusiveFiller,
                    order.exclusivityOverrideBps,
                    input.token,
                    input.startAmount,
                    input.endAmount,
                    order.outputs.hash()
                )
            )
        );
    }
}
