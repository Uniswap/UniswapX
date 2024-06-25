// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {OrderInfo, InputToken, OutputToken} from "../base/ReactorStructs.sol";
import {OrderInfoLib} from "./OrderInfoLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

struct PriorityInput {
    ERC20 token;
    uint256 amount;
    // the extra amount of input to be paid per wei of priority fee
    uint256 bpsPerPriorityFeeWei;
}

struct PriorityOutput {
    address token;
    uint256 amount;
    // the extra amount of output to be paid per wei of priority fee
    uint256 bpsPerPriorityFeeWei;
    address recipient;
}

/// @dev External struct used to specify priority orders
struct PriorityOrder {
    // generic order information
    OrderInfo info;
    // the block at which the order becomes active
    uint256 startBlock;
    // The tokens that the swapper will provide when settling the order
    PriorityInput input;
    // The tokens that must be received to satisfy the order
    PriorityOutput[] outputs;
}

/// @notice helpers for handling priority order objects
library PriorityOrderLib {
    using OrderInfoLib for OrderInfo;

    bytes private constant PRIORITY_OUTPUT_TOKEN_TYPE =
        "PriorityOutput(address token,uint256 amount,uint256 bpsPerPriorityFeeWei,address recipient)";

    bytes32 private constant PRIORITY_OUTPUT_TOKEN_TYPE_HASH = keccak256(PRIORITY_OUTPUT_TOKEN_TYPE);

    bytes internal constant ORDER_TYPE = abi.encodePacked(
        "PriorityOrder(",
        "OrderInfo info,",
        "uint256 startBlock,",
        "address inputToken,",
        "uint256 inputAmount,",
        "uint256 inputBpsPerPriorityFeeWei,",
        "PriorityOutput[] outputs)",
        OrderInfoLib.ORDER_INFO_TYPE,
        PRIORITY_OUTPUT_TOKEN_TYPE
    );
    bytes32 internal constant ORDER_TYPE_HASH = keccak256(ORDER_TYPE);

    string private constant TOKEN_PERMISSIONS_TYPE = "TokenPermissions(address token,uint256 amount)";
    string internal constant PERMIT2_ORDER_TYPE =
        string(abi.encodePacked("PriorityOrder witness)", ORDER_TYPE, TOKEN_PERMISSIONS_TYPE));

    /// @notice returns the hash of an output token struct
    function hash(PriorityOutput memory output) private pure returns (bytes32) {
        return keccak256(
            abi.encode(
                PRIORITY_OUTPUT_TOKEN_TYPE_HASH,
                output.token,
                output.amount,
                output.bpsPerPriorityFeeWei,
                output.recipient
            )
        );
    }

    /// @notice returns the hash of an output token struct
    function hash(PriorityOutput[] memory outputs) private pure returns (bytes32) {
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
    function hash(PriorityOrder memory order) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                ORDER_TYPE_HASH,
                order.info.hash(),
                order.startBlock,
                order.input.token,
                order.input.amount,
                order.input.bpsPerPriorityFeeWei,
                hash(order.outputs)
            )
        );
    }
}
