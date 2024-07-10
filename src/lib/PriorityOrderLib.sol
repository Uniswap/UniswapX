// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {OrderInfo, InputToken, OutputToken} from "../base/ReactorStructs.sol";
import {OrderInfoLib} from "./OrderInfoLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

struct PriorityCosignerData {
    // the block at which the order can be executed (overrides auctionStartBlock)
    uint256 auctionTargetBlock;
}

struct PriorityInput {
    ERC20 token;
    uint256 amount;
    // the less amount of input to be received per wei of priority fee
    uint256 mpsPerPriorityFeeWei;
}

struct PriorityOutput {
    address token;
    uint256 amount;
    // the extra amount of output to be paid per wei of priority fee
    uint256 mpsPerPriorityFeeWei;
    address recipient;
}

/// @dev External struct used to specify priority orders
struct PriorityOrder {
    // generic order information
    OrderInfo info;
    // The address which must cosign the full order
    address cosigner;
    // the block at which the order can be executed
    uint256 auctionStartBlock;
    // the baseline priority fee for the order, above which additional taxes are applied
    uint256 baselinePriorityFeeWei;
    // The tokens that the swapper will provide when settling the order
    PriorityInput input;
    // The tokens that must be received to satisfy the order
    PriorityOutput[] outputs;
    // signed over by the cosigner
    PriorityCosignerData cosignerData;
    // signature from the cosigner over (orderHash || cosignerData)
    bytes cosignature;
}

/// @notice helpers for handling priority order objects
library PriorityOrderLib {
    using OrderInfoLib for OrderInfo;

    bytes private constant PRIORITY_INPUT_TOKEN_TYPE =
        "PriorityInput(address token,uint256 amount,uint256 mpsPerPriorityFeeWei)";

    bytes32 private constant PRIORITY_INPUT_TOKEN_TYPE_HASH = keccak256(PRIORITY_INPUT_TOKEN_TYPE);

    bytes private constant PRIORITY_OUTPUT_TOKEN_TYPE =
        "PriorityOutput(address token,uint256 amount,uint256 mpsPerPriorityFeeWei,address recipient)";

    bytes32 private constant PRIORITY_OUTPUT_TOKEN_TYPE_HASH = keccak256(PRIORITY_OUTPUT_TOKEN_TYPE);

    bytes internal constant ORDER_TYPE = abi.encodePacked(
        "PriorityOrder(",
        "OrderInfo info,",
        "address cosigner,",
        "uint256 auctionStartBlock,",
        "uint256 baselinePriorityFeeWei,",
        "PriorityInput input,",
        "PriorityOutput[] outputs)",
        OrderInfoLib.ORDER_INFO_TYPE,
        PRIORITY_INPUT_TOKEN_TYPE,
        PRIORITY_OUTPUT_TOKEN_TYPE
    );
    bytes32 internal constant ORDER_TYPE_HASH = keccak256(ORDER_TYPE);

    string private constant TOKEN_PERMISSIONS_TYPE = "TokenPermissions(address token,uint256 amount)";
    string internal constant PERMIT2_ORDER_TYPE =
        string(abi.encodePacked("PriorityOrder witness)", ORDER_TYPE, TOKEN_PERMISSIONS_TYPE));

    /// @notice returns the hash of an input token struct
    function hash(PriorityInput memory input) private pure returns (bytes32) {
        return
            keccak256(abi.encode(PRIORITY_INPUT_TOKEN_TYPE_HASH, input.token, input.amount, input.mpsPerPriorityFeeWei));
    }

    /// @notice returns the hash of an output token struct
    function hash(PriorityOutput memory output) private pure returns (bytes32) {
        return keccak256(
            abi.encode(
                PRIORITY_OUTPUT_TOKEN_TYPE_HASH,
                output.token,
                output.amount,
                output.mpsPerPriorityFeeWei,
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
                order.cosigner,
                order.auctionStartBlock,
                order.baselinePriorityFeeWei,
                hash(order.input),
                hash(order.outputs)
            )
        );
    }
}
