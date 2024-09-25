// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @dev An uint16 array of max 16 values packed into a single uint256
type Uint16Array is uint256;

error IndexOutOfBounds();
error InvalidArrLength();

function toUint256(uint16[] memory inputArray) pure returns (uint256 uint16Array) {
    return Uint16Array.unwrap(toUint16Array(inputArray));
}

function fromUnderlying(uint256 value) pure returns (Uint16Array) {
    return Uint16Array.wrap(value);
}

// Helper for creating a packed uint256 from a uint16 array
function toUint16Array(uint16[] memory inputArray) pure returns (Uint16Array uint16Array) {
    if (inputArray.length > 16) {
        revert InvalidArrLength();
    }
    uint256 packedData = 0;

    for (uint256 i = 0; i < inputArray.length; i++) {
        packedData |= uint256(inputArray[i]) << (i * 16);
    }

    uint16Array = Uint16Array.wrap(packedData);
}

library Uint16ArrayLibrary {
    // Retrieve the nth uint16 value from a packed uint256
    function getElement(Uint16Array packedData, uint256 n) internal pure returns (uint16) {
        if (n >= 16) {
            revert IndexOutOfBounds();
        }
        unchecked {
            uint256 shiftAmount = n * 16;
            uint16 result = uint16((Uint16Array.unwrap(packedData) >> shiftAmount) & 0xFFFF);
            return result;
        }
    }
}
