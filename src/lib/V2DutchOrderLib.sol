// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {OrderInfo} from "../base/ReactorStructs.sol";
import {DutchOutput, DutchInput, DutchOrderLib} from "./DutchOrderLib.sol";
import {OrderInfoLib} from "./OrderInfoLib.sol";

struct CosignerData {
    // The time at which the DutchOutputs start decaying
    uint256 decayStartTime;
    // The time at which price becomes static
    uint256 decayEndTime;
    // Encoded exclusiveFiller, inputOverride, and outputOverrides, where needed
    // First byte: fff0 0000 where f is a flag signalling inclusion of the 3 variables
    // exclusiveFiller: The address who has exclusive rights to the order until decayStartTime
    // inputOverride: The number of tokens that the swapper will provide when settling the order
    // outputOverrides: The tokens that must be received to satisfy the order
    bytes extraData;
}

struct V2DutchOrder {
    // generic order information
    OrderInfo info;
    // The address which must cosign the full order
    address cosigner;
    // The tokens that the swapper will provide when settling the order
    DutchInput input;
    // The tokens that must be received to satisfy the order
    DutchOutput[] outputs;
    // signed over by the cosigner
    CosignerData cosignerData;
    // signature from the cosigner over (orderHash || cosignerData)
    bytes cosignature;
}

/// @notice helpers for handling v2 dutch order objects
library V2DutchOrderLib {
    using DutchOrderLib for DutchOutput[];
    using OrderInfoLib for OrderInfo;

    bytes internal constant V2_DUTCH_ORDER_TYPE = abi.encodePacked(
        "V2DutchOrder(",
        "OrderInfo info,",
        "address cosigner,",
        "address inputToken,",
        "uint256 inputStartAmount,",
        "uint256 inputEndAmount,",
        "DutchOutput[] outputs)"
    );

    bytes internal constant ORDER_TYPE =
        abi.encodePacked(V2_DUTCH_ORDER_TYPE, DutchOrderLib.DUTCH_OUTPUT_TYPE, OrderInfoLib.ORDER_INFO_TYPE);
    bytes32 internal constant ORDER_TYPE_HASH = keccak256(ORDER_TYPE);

    /// @dev Note that sub-structs have to be defined in alphabetical order in the EIP-712 spec
    string internal constant PERMIT2_ORDER_TYPE = string(
        abi.encodePacked(
            "V2DutchOrder witness)",
            DutchOrderLib.DUTCH_OUTPUT_TYPE,
            OrderInfoLib.ORDER_INFO_TYPE,
            DutchOrderLib.TOKEN_PERMISSIONS_TYPE,
            V2_DUTCH_ORDER_TYPE
        )
    );

    /// @notice hash the given order
    /// @param order the order to hash
    /// @return the eip-712 order hash
    function hash(V2DutchOrder memory order) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                ORDER_TYPE_HASH,
                order.info.hash(),
                order.cosigner,
                order.input.token,
                order.input.startAmount,
                order.input.endAmount,
                order.outputs.hash()
            )
        );
    }
}

library CosignerExtraDataLib {
    bytes32 constant EXCL_FILLER_FLAG_MASK = 0x8000000000000000000000000000000000000000000000000000000000000000;
    bytes32 constant INPUT_OVERRIDE_FLAG_MASK = 0x4000000000000000000000000000000000000000000000000000000000000000;
    bytes32 constant OUTPUT_OVERRIDE_FLAG_MASK = 0x2000000000000000000000000000000000000000000000000000000000000000;
    bytes32 constant OUTPUTS_LENGTH_FLAG_MASK = 0x1F00000000000000000000000000000000000000000000000000000000000000;

    // "True" first bit of byte 1 signals that there is an exclusive filler
    function hasExclusiveFiller(bytes memory extraData) internal pure returns (bool flag) {
        if (extraData.length == 0) return false;
        assembly {
            flag := and(mload(add(extraData, 32)), EXCL_FILLER_FLAG_MASK)
        }
    }

    // "True" second bit of byte 1 signals that there is an input override
    function hasInputOverride(bytes memory extraData) internal pure returns (bool flag) {
        if (extraData.length == 0) return false;
        assembly {
            flag := and(mload(add(extraData, 32)), INPUT_OVERRIDE_FLAG_MASK)
        }
    }

    // "True" third bit of byte 1 signals that there is an output override
    function hasOutputOverrides(bytes memory extraData) internal pure returns (bool flag) {
        if (extraData.length == 0) return false;
        assembly {
            flag := and(mload(add(extraData, 32)), OUTPUT_OVERRIDE_FLAG_MASK)
        }
    }

    function decodeExtraParameters(bytes memory extraData)
        internal
        pure
        returns (address filler, uint256 inputOverride, uint256[] memory outputOverrides)
    {
        if (extraData.length == 0) return (filler, inputOverride, outputOverrides);
        // The first 32 bytes are length
        // The first byte (index 0) only contains flags of whether each field is included in the bytes
        // So we can start from index 1 (after 32) to start decoding each field
        uint256 bytesOffset = 33;

        if (hasExclusiveFiller(extraData)) {
            // + 20 bytes for address, - 32 bytes for the length offset
            require(extraData.length >= bytesOffset - 12);
            assembly {
                // it loads a full 32 bytes, shift right 96 bits so only the address remains
                filler := shr(96, mload(add(extraData, bytesOffset)))
            }
            bytesOffset += 20;
        }

        if (hasInputOverride(extraData)) {
            // + 32 bytes for uint256, - 32 bytes for the length offset
            require(extraData.length >= bytesOffset);
            assembly {
                inputOverride := mload(add(extraData, bytesOffset))
            }
            bytesOffset += 32;
        }

        if (hasOutputOverrides(extraData)) {
            uint256 length;
            assembly {
                length := shr(248, and(mload(add(extraData, 32)), OUTPUTS_LENGTH_FLAG_MASK))
            }

            // each element of the array is 32 bytes, - 32 bytes for the length offset
            require(extraData.length == bytesOffset + (length - 1) * 32);
            outputOverrides = new uint256[](length);

            uint256 outputOverride;
            for (uint256 i = 0; i < length; i++) {
                assembly {
                    outputOverride := mload(add(extraData, add(bytesOffset, mul(i, 32))))
                }
                outputOverrides[i] = outputOverride;
            }
        }
    }
}
