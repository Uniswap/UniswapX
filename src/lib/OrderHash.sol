// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {OrderInfo, InputToken, OutputToken} from "../base/ReactorStructs.sol";

/// @notice some shared order hashing logic
library OrderHash {
    bytes public constant ORDER_INFO_TYPE = "OrderInfo(address reactor,address offerer,uint256 nonce,uint256 deadline)";
    bytes public constant INPUT_TOKEN_TYPE = "InputToken(address token,uint256 amount)";
    bytes public constant OUTPUT_TOKEN_TYPE = "OutputToken(address token,uint256 amount,address recipient)";
    bytes32 public constant ORDER_INFO_TYPE_HASH = keccak256(ORDER_INFO_TYPE);
    bytes32 public constant INPUT_TOKEN_TYPE_HASH = keccak256(INPUT_TOKEN_TYPE);
    bytes32 public constant OUTPUT_TOKEN_TYPE_HASH = keccak256(OUTPUT_TOKEN_TYPE);

    /// @notice returns the hash of an order info struct
    function hash(OrderInfo memory info) internal pure returns (bytes32) {
        return keccak256(abi.encode(ORDER_INFO_TYPE_HASH, info.reactor, info.offerer, info.nonce, info.deadline));
    }

    /// @notice returns the hash of an input token struct
    function hash(InputToken memory input) internal pure returns (bytes32) {
        return keccak256(abi.encode(INPUT_TOKEN_TYPE_HASH, input.token, input.amount));
    }

    /// @notice returns the hash of an output token struct
    function hash(OutputToken memory output) internal pure returns (bytes32) {
        return keccak256(abi.encode(OUTPUT_TOKEN_TYPE_HASH, output.token, output.amount, output.recipient));
    }

    /// @notice returns the hash of an output token struct
    function hash(OutputToken[] memory outputs) internal pure returns (bytes32) {
        bytes32[] memory outputHashes = new bytes32[](outputs.length);
        for (uint256 i = 0; i < outputs.length; i++) {
            outputHashes[i] = hash(outputs[i]);
        }
        return keccak256(abi.encodePacked(outputHashes));
    }
}
