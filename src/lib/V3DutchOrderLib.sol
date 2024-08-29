// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {DutchOrderLib} from "./DutchOrderLib.sol";
import {OrderInfo} from "../base/ReactorStructs.sol";
import {OrderInfoLib} from "./OrderInfoLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

struct CosignerData {
    // The block at which the input or outputs start decaying
    uint256 decayStartBlock;
    // The address who has exclusive rights to the order until decayStartBlock
    address exclusiveFiller;
    // The amount in bps that a non-exclusive filler needs to improve the outputs by to be able to fill the order
    uint256 exclusivityOverrideBps;
    // The tokens that the swapper will provide when settling the order
    uint256 inputAmount;
    // The tokens that must be received to satisfy the order
    uint256[] outputAmounts;
}

struct V3DutchOrder {
    // generic order information
    OrderInfo info;
    // The address which must cosign the full order
    address cosigner;
    // The tokens that the swapper will provide when settling the order
    V3DutchInput baseInput;
    // The tokens that must be received to satisfy the order
    V3DutchOutput[] baseOutputs;
    // signed over by the cosigner
    CosignerData cosignerData;
    // signature from the cosigner over (orderHash || cosignerData)
    bytes cosignature;
}

/// @dev The changes in tokens (positive or negative) to subtract from the start amount
/// @dev The relativeBlocks should be strictly increasing
struct V3Decay {
    // 16 uint16 values packed
    // Can represent curves with points 2^16 blocks into the future
    uint256 relativeBlocks;
    int256[] relativeAmounts;
}

/// @dev An amount of input tokens that increases non-linearly over time
struct V3DutchInput {
    // The ERC20 token address
    ERC20 token;
    // The amount of tokens at the starting block
    uint256 startAmount;
    // The amount of tokens at the each future block
    V3Decay curve;
    // The max amount of the curve
    uint256 maxAmount;
}

/// @dev An amount of output tokens that decreases non-linearly over time
struct V3DutchOutput {
    // The ERC20 token address (or native ETH address)
    address token;
    // The amount of tokens at the start of the time period
    uint256 startAmount;
    // The amount of tokens at the each future block
    V3Decay curve;
    // The address who must receive the tokens to satisfy the order
    address recipient;
}

/// @notice helpers for handling custom curve order objects
library V3DutchOrderLib {
    using OrderInfoLib for OrderInfo;

    bytes internal constant NON_LINEAR_DUTCH_ORDER_TYPE = abi.encodePacked(
        "V3DutchOrder(",
        "OrderInfo info,",
        "address cosigner,",
        "V3DutchInput baseInput,",
        "V3DutchOutput[] baseOutputs)"
    );
    bytes internal constant NON_LINEAR_DUTCH_OUTPUT_TYPE = abi.encodePacked(
        "V3DutchOutput(", "address token,", "uint256 startAmount,", "V3Decay curve,", "address recipient)"
    );
    bytes32 internal constant NON_LINEAR_DUTCH_OUTPUT_TYPE_HASH = keccak256(NON_LINEAR_DUTCH_OUTPUT_TYPE);
    bytes internal constant NON_LINEAR_DECAY_TYPE =
        abi.encodePacked("V3Decay(", "uint256 relativeBlocks,", "int256[] relativeAmounts)");
    bytes32 internal constant NON_LINEAR_DECAY_TYPE_HASH = keccak256(NON_LINEAR_DECAY_TYPE);

    bytes internal constant ORDER_TYPE = abi.encodePacked(
        NON_LINEAR_DECAY_TYPE, NON_LINEAR_DUTCH_ORDER_TYPE, NON_LINEAR_DUTCH_OUTPUT_TYPE, OrderInfoLib.ORDER_INFO_TYPE
    );
    bytes32 internal constant ORDER_TYPE_HASH = keccak256(ORDER_TYPE);

    /// @dev Note that sub-structs have to be defined in alphabetical order in the EIP-712 spec
    string internal constant PERMIT2_ORDER_TYPE = string(
        abi.encodePacked(
            "V3DutchOrder witness)",
            NON_LINEAR_DECAY_TYPE,
            NON_LINEAR_DUTCH_ORDER_TYPE,
            NON_LINEAR_DUTCH_OUTPUT_TYPE,
            OrderInfoLib.ORDER_INFO_TYPE,
            DutchOrderLib.TOKEN_PERMISSIONS_TYPE
        )
    );

    function hash(V3Decay memory curve) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                NON_LINEAR_DECAY_TYPE_HASH, curve.relativeBlocks, keccak256(abi.encodePacked(curve.relativeAmounts))
            )
        );
    }

    /// @notice hash the given input
    /// @param input the input to hash
    /// @return the eip-712 input hash
    function hash(V3DutchInput memory input) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                NON_LINEAR_DUTCH_OUTPUT_TYPE_HASH, input.token, input.startAmount, hash(input.curve), input.maxAmount
            )
        );
    }

    /// @notice hash the given output
    /// @param output the output to hash
    /// @return the eip-712 output hash
    function hash(V3DutchOutput memory output) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                NON_LINEAR_DUTCH_OUTPUT_TYPE_HASH,
                output.token,
                output.startAmount,
                hash(output.curve),
                output.recipient
            )
        );
    }

    /// @notice hash the given outputs
    /// @param outputs the outputs to hash
    /// @return the eip-712 outputs hash
    function hash(V3DutchOutput[] memory outputs) internal pure returns (bytes32) {
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
    function hash(V3DutchOrder memory order) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                ORDER_TYPE_HASH, order.info.hash(), order.cosigner, hash(order.baseInput), hash(order.baseOutputs)
            )
        );
    }
}
