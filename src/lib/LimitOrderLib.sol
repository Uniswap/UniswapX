// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {OrderInfo, InputToken, OutputToken} from "../base/ReactorStructs.sol";

/// @dev External struct used to specify simple limit orders
struct LimitOrder {
    // generic order information
    OrderInfo info;
    // The tokens that the offerer will provide when settling the order
    InputToken input;
    // The tokens that must be received to satisfy the order
    OutputToken[] outputs;
}

/// @notice helpers for handling limit order objects
library LimitOrderLib {
    bytes private constant OUTPUT_TOKEN_TYPE =
        "OutputToken(address token,uint256 amount,address recipient,bool isFeeOutput)";
    bytes32 private constant OUTPUT_TOKEN_TYPE_HASH = keccak256(OUTPUT_TOKEN_TYPE);

    bytes internal constant ORDER_TYPE = abi.encodePacked(
        "LimitOrder(",
        "address reactor,",
        "address offerer,",
        "uint256 nonce,",
        "uint256 deadline,",
        "uint256 validationContract,",
        "uint256 validationData,",
        "address inputToken,",
        "uint256 inputAmount,",
        "OutputToken[] outputs)",
        OUTPUT_TOKEN_TYPE
    );
    bytes32 internal constant ORDER_TYPE_HASH = keccak256(ORDER_TYPE);

    string private constant TOKEN_PERMISSIONS_TYPE = "TokenPermissions(address token,uint256 amount)";
    string internal constant PERMIT2_ORDER_TYPE =
        string(abi.encodePacked("LimitOrder witness)", ORDER_TYPE, TOKEN_PERMISSIONS_TYPE));

    /// @notice returns the hash of an output token struct
    function hash(OutputToken memory output) private pure returns (bytes32) {
        return keccak256(
            abi.encode(OUTPUT_TOKEN_TYPE_HASH, output.token, output.amount, output.recipient, output.isFeeOutput)
        );
    }

    /// @notice returns the hash of an output token struct
    function hash(OutputToken[] memory outputs) private pure returns (bytes32) {
        bytes32[] memory outputHashes = new bytes32[](outputs.length);
        unchecked{
            for (uint256 i = 0; i < outputs.length; i++) {
                outputHashes[i] = hash(outputs[i]);
            }
        }
        return keccak256(abi.encodePacked(outputHashes));
    }

    /// @notice hash the given order
    /// @param order the order to hash
    /// @return the eip-712 order hash
    function hash(LimitOrder memory order) internal pure returns (bytes32) {
        OrderInfo memory info = order.info;
        return keccak256(
            abi.encode(
                ORDER_TYPE_HASH,
                info.reactor,
                info.offerer,
                info.nonce,
                info.deadline,
                info.validationContract,
                keccak256(info.validationData),
                order.input.token,
                order.input.amount,
                hash(order.outputs)
            )
        );
    }
}
