// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {OrderInfo} from "../base/ReactorStructs.sol";
import {OrderInfoLib} from "./OrderInfoLib.sol";
import {PriorityInput, PriorityOutput, PriorityCosignerData} from "../../lib/PriorityOrderLib.sol";

/// @dev External struct used to specify priority orders
struct PriorityOrder {
    // generic order information
    OrderInfo info;
    // The address which may cosign the order
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

    bytes internal constant PRIORITY_INPUT_TOKEN_TYPE =
        "PriorityInput(address token,uint256 amount,uint256 mpsPerPriorityFeeWei)";

    bytes32 internal constant PRIORITY_INPUT_TOKEN_TYPE_HASH = keccak256(PRIORITY_INPUT_TOKEN_TYPE);

    bytes internal constant PRIORITY_OUTPUT_TOKEN_TYPE =
        "PriorityOutput(address token,uint256 amount,uint256 mpsPerPriorityFeeWei,address recipient)";

    bytes32 internal constant PRIORITY_OUTPUT_TOKEN_TYPE_HASH = keccak256(PRIORITY_OUTPUT_TOKEN_TYPE);

    string internal constant TOKEN_PERMISSIONS_TYPE = "TokenPermissions(address token,uint256 amount)";

    // Witness wrapper that includes the resolver address for security
    bytes internal constant PRIORITY_ORDER_WITNESS_TYPE =
        abi.encodePacked("PriorityOrderWitness(", "address resolver,", "PriorityOrder order)");

    bytes32 internal constant PRIORITY_ORDER_WITNESS_TYPE_HASH = keccak256(
        abi.encodePacked(
            PRIORITY_ORDER_WITNESS_TYPE,
            OrderInfoLib.ORDER_INFO_TYPE,
            PRIORITY_INPUT_TOKEN_TYPE,
            TOPLEVEL_PRIORITY_ORDER_TYPE,
            PRIORITY_OUTPUT_TOKEN_TYPE
        )
    );

    // EIP712 notes that nested structs should be ordered alphabetically.
    // With our added PriorityOrderWitness witness, the top level type becomes
    // "PermitWitnessTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline,PriorityOrderWitness witness)"
    // Meaning we order the nested structs as follows:
    // OrderInfo, PriorityInput, PriorityOrder, PriorityOrderWitness, PriorityOutput
    string internal constant PERMIT2_ORDER_TYPE = string(
        abi.encodePacked(
            "PriorityOrderWitness witness)",
            OrderInfoLib.ORDER_INFO_TYPE,
            PRIORITY_INPUT_TOKEN_TYPE,
            TOPLEVEL_PRIORITY_ORDER_TYPE,
            PRIORITY_ORDER_WITNESS_TYPE,
            PRIORITY_OUTPUT_TOKEN_TYPE,
            TOKEN_PERMISSIONS_TYPE
        )
    );

    bytes internal constant TOPLEVEL_PRIORITY_ORDER_TYPE = abi.encodePacked(
        "PriorityOrder(",
        "OrderInfo info,",
        "address cosigner,",
        "uint256 auctionStartBlock,",
        "uint256 baselinePriorityFeeWei,",
        "PriorityInput input,",
        "PriorityOutput[] outputs)"
    );

    // EIP712 notes that nested structs should be ordered alphabetically:
    // OrderInfo, PriorityInput, PriorityOutput
    bytes internal constant ORDER_TYPE = abi.encodePacked(
        TOPLEVEL_PRIORITY_ORDER_TYPE,
        OrderInfoLib.ORDER_INFO_TYPE,
        PRIORITY_INPUT_TOKEN_TYPE,
        PRIORITY_OUTPUT_TOKEN_TYPE
    );
    bytes32 internal constant ORDER_TYPE_HASH = keccak256(ORDER_TYPE);

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

    /// @notice returns the hash of an array of output token struct
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

    /// @notice Compute the witness hash that includes the resolver address
    /// @param order the priorityOrder
    /// @param resolver the auction resolver address
    /// @return witness hash that binds the order to the resolver
    function witnessHash(PriorityOrder memory order, address resolver) internal pure returns (bytes32) {
        return keccak256(abi.encode(PRIORITY_ORDER_WITNESS_TYPE_HASH, resolver, hash(order)));
    }

    /// @notice get the digest of the cosigner data
    /// @param order the priorityOrder
    /// @param orderHash the hash of the order
    /// @return the digest of the cosigner data
    function cosignerDigest(PriorityOrder memory order, bytes32 orderHash) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(orderHash, block.chainid, abi.encode(order.cosignerData)));
    }
}
