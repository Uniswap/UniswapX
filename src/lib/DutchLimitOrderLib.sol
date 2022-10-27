// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {OrderInfo, InputToken, OutputToken} from "../base/ReactorStructs.sol";

/// @dev An amount of tokens that decays linearly over time
struct DutchOutput {
    // The ERC20 token address
    address token;
    // The amount of tokens at the start of the time period
    uint256 startAmount;
    // The amount of tokens at the end of the time period
    uint256 endAmount;
    // The address who must receive the tokens to satisfy the order
    address recipient;
}

struct DutchLimitOrder {
    // generic order information
    OrderInfo info;
    // The time at which the DutchOutputs start decaying
    uint256 startTime;
    // endTime is implicitly info.deadline

    // The tokens that the offerer will provide when settling the order
    InputToken input;
    // The tokens that must be received to satisfy the order
    DutchOutput[] outputs;
}

/// @notice helpers for handling dutch limit order objects
library DutchLimitOrderLib {
    string constant ORDER_TYPE_NAME = "DutchLimitOrder";
    bytes private constant DUTCH_OUTPUT_TYPE =
        "DutchOutput(address token,uint256 startAmount,uint256 endAmount,address recipient)";
    bytes32 private constant DUTCH_OUTPUT_TYPE_HASH = keccak256(DUTCH_OUTPUT_TYPE);
    bytes constant ORDER_TYPE = abi.encodePacked(
        "DutchLimitOrder(",
        "address reactor,",
        "address offerer,",
        "uint256 nonce,",
        "uint256 deadline,",
        "uint256 startTime,",
        "address inputToken,",
        "uint256 inputAmount,",
        "DutchOutput[] outputs)",
        DUTCH_OUTPUT_TYPE
    );
    bytes32 private constant ORDER_TYPE_HASH = keccak256(ORDER_TYPE);

    /// @notice hash the given order
    /// @param order the order to hash
    /// @return the eip-712 order hash
    function hash(DutchLimitOrder memory order) internal pure returns (bytes32) {
        bytes32[] memory outputHashes = new bytes32[](order.outputs.length);
        for (uint256 i = 0; i < order.outputs.length; i++) {
            outputHashes[i] = keccak256(
                abi.encode(
                    DUTCH_OUTPUT_TYPE_HASH,
                    order.outputs[i].token,
                    order.outputs[i].startAmount,
                    order.outputs[i].endAmount,
                    order.outputs[i].recipient
                )
            );
        }
        bytes32 outputHash = keccak256(abi.encodePacked(outputHashes));

        return keccak256(
            abi.encode(
                ORDER_TYPE_HASH,
                order.info.reactor,
                order.info.offerer,
                order.info.nonce,
                order.info.deadline,
                order.startTime,
                order.input.token,
                order.input.amount,
                outputHash
            )
        );
    }
}
