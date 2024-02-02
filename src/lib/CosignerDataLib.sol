// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

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
