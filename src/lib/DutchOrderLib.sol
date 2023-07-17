// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {OrderInfo} from "../base/ReactorStructs.sol";
import {OrderInfoLib} from "./OrderInfoLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

/// @dev An amount of output tokens that decreases linearly over time
struct DutchOutput {
    // The ERC20 token address (or native ETH address)
    address token;
    // The amount of tokens at the start of the time period
    uint256 startAmount;
    // The amount of tokens at the end of the time period
    uint256 endAmount;
    // The address who must receive the tokens to satisfy the order
    address recipient;
}

/// @dev An amount of input tokens that increases linearly over time
struct DutchInput {
    // The ERC20 token address
    ERC20 token;
    // The amount of tokens at the start of the time period
    uint256 startAmount;
    // The amount of tokens at the end of the time period
    uint256 endAmount;
}

struct DutchOrder {
    // generic order information
    OrderInfo info;
    // The time at which the DutchOutputs start decaying
    uint256 decayStartTime;
    // The time at which price becomes static
    uint256 decayEndTime;
    // The tokens that the swapper will provide when settling the order
    DutchInput input;
    // The tokens that must be received to satisfy the order
    DutchOutput[] outputs;
}

/// @notice helpers for handling dutch order objects
library DutchOrderLib {
    using OrderInfoLib for OrderInfo;

    bytes internal constant DUTCH_OUTPUT_TYPE =
        "DutchOutput(address token,uint256 startAmount,uint256 endAmount,address recipient)";
    bytes32 internal constant DUTCH_OUTPUT_TYPE_HASH = keccak256(DUTCH_OUTPUT_TYPE);

    bytes internal constant DUTCH_LIMIT_ORDER_TYPE = abi.encodePacked(
        "DutchOrder(",
        "OrderInfo info,",
        "uint256 decayStartTime,",
        "uint256 decayEndTime,",
        "address inputToken,",
        "uint256 inputStartAmount,",
        "uint256 inputEndAmount,",
        "DutchOutput[] outputs)"
    );

    /// @dev Note that sub-structs have to be defined in alphabetical order in the EIP-712 spec
    bytes internal constant ORDER_TYPE =
        abi.encodePacked(DUTCH_LIMIT_ORDER_TYPE, DUTCH_OUTPUT_TYPE, OrderInfoLib.ORDER_INFO_TYPE);
    bytes32 internal constant ORDER_TYPE_HASH = keccak256(ORDER_TYPE);

    string internal constant TOKEN_PERMISSIONS_TYPE = "TokenPermissions(address token,uint256 amount)";
    string internal constant PERMIT2_ORDER_TYPE =
        string(abi.encodePacked("DutchOrder witness)", ORDER_TYPE, TOKEN_PERMISSIONS_TYPE));

    /// @notice hash the given output
    /// @param output the output to hash
    /// @return the eip-712 output hash
    function hash(DutchOutput memory output) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(DUTCH_OUTPUT_TYPE_HASH, output.token, output.startAmount, output.endAmount, output.recipient)
        );
    }

    /// @notice hash the given outputs
    /// @param outputs the outputs to hash
    /// @return the eip-712 outputs hash
    function hash(DutchOutput[] memory outputs) internal pure returns (bytes32) {
        unchecked {
            bytes memory packedHashes = new bytes(32 * outputs.length);

            for (uint256 i = 0; i < outputs.length; i++) {
                bytes32 outputHash = hash(outputs[i]);
                assembly {
                    mstore(add(add(packedHashes, 0x20), mul(i, 0x20)), outputHash)
                }
            }

            return keccak256(packedHashes);
        }
    }

    /// @notice hash the given order
    /// @param order the order to hash
    /// @return the eip-712 order hash
    function hash(DutchOrder memory order) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                ORDER_TYPE_HASH,
                order.info.hash(),
                order.decayStartTime,
                order.decayEndTime,
                order.input.token,
                order.input.startAmount,
                order.input.endAmount,
                hash(order.outputs)
            )
        );
    }
}
