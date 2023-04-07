// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {OrderInfo} from "../base/ReactorStructs.sol";

/// @dev An amount of output tokens that decreases linearly over time
struct DutchOutput {
    // The ERC20 token address
    address token;
    // The amount of tokens at the start of the time period
    uint256 startAmount;
    // The amount of tokens at the end of the time period
    uint256 endAmount;
    // The address who must receive the tokens to satisfy the order
    address recipient;
    // True if this output represents a fee
    bool isFeeOutput;
}

/// @dev An amount of input tokens that increases linearly over time
struct DutchInput {
    // The ERC20 token address
    address token;
    // The amount of tokens at the start of the time period
    uint256 startAmount;
    // The amount of tokens at the end of the time period
    uint256 endAmount;
}

struct DutchLimitOrder {
    // generic order information
    OrderInfo info;
    // The time at which the DutchOutputs start decaying
    uint256 startTime;
    // The time at which price becomes static
    uint256 endTime;
    // The tokens that the offerer will provide when settling the order
    DutchInput input;
    // The tokens that must be received to satisfy the order
    DutchOutput[] outputs;
}

/// @notice helpers for handling dutch limit order objects
library DutchLimitOrderLib {
    bytes internal constant DUTCH_OUTPUT_TYPE =
        "DutchOutput(address token,uint256 startAmount,uint256 endAmount,address recipient,bool isFeeOutput)";
    bytes32 internal constant DUTCH_OUTPUT_TYPE_HASH = keccak256(DUTCH_OUTPUT_TYPE);

    bytes internal constant ORDER_TYPE = abi.encodePacked(
        "DutchLimitOrder(",
        "address reactor,",
        "address offerer,",
        "uint256 nonce,",
        "uint256 deadline,",
        "address validationContract,",
        "bytes validationData,",
        "uint256 startTime,",
        "uint256 endTime,",
        "address inputToken,",
        "uint256 inputStartAmount,",
        "uint256 inputEndAmount,",
        "DutchOutput[] outputs)",
        DUTCH_OUTPUT_TYPE
    );
    bytes32 internal constant ORDER_TYPE_HASH = keccak256(ORDER_TYPE);

    string internal constant TOKEN_PERMISSIONS_TYPE = "TokenPermissions(address token,uint256 amount)";
    string internal constant PERMIT2_ORDER_TYPE =
        string(abi.encodePacked("DutchLimitOrder witness)", ORDER_TYPE, TOKEN_PERMISSIONS_TYPE));

    function hash(DutchOutput memory output) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                DUTCH_OUTPUT_TYPE_HASH,
                output.token,
                output.startAmount,
                output.endAmount,
                output.recipient,
                output.isFeeOutput
            )
        );
    }

    function hash(DutchOutput[] memory outputs) internal pure returns (bytes32) {
        bytes32[] memory outputHashes = new bytes32[](outputs.length);
        unchecked {
            for (uint256 i = 0; i < outputs.length; i++) {
                outputHashes[i] = hash(outputs[i]);
            }
        }
        return keccak256(abi.encodePacked(outputHashes));
    }

    /// @notice hash the given order
    /// @param order the order to hash
    /// @return the eip-712 order hash
    function hash(DutchLimitOrder memory order) internal pure returns (bytes32) {
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
                order.input.token,
                order.input.startAmount,
                order.input.endAmount,
                hash(order.outputs)
            )
        );
    }
}
