pragma solidity ^0.8.0;

library Util {
    error NegativeUint();
    error IndexOutOfBounds();
    error InvalidArrLength();

    function subIntFromUint(int256 a, uint256 b) public pure returns (uint256) {
        if (a < 0) {
            // If a is negative, add its absolute value to b
            return b + uint256(-a);
        } else {
            // If a is positive, subtract it from b
            if(b < uint256(a)) {
                revert NegativeUint();
            }
            
            return b - uint256(a);
        }
    }

    // Retrieve the nth uint16 value from a packed uint256
    function getUint16FromPacked(uint256 packedData, uint256 n) public pure returns (uint16) {
        if(n >= 16) {
            revert IndexOutOfBounds();
        }
        uint256 shiftAmount = n * 16;
        uint16 result = uint16((packedData >> shiftAmount) & 0xFFFF);
        return result;
    }

    // Helper for creating a packed uint256 from a uint16 array
    function packUint16Array(uint16[] memory inputArray) public pure returns (uint256) {
        if(inputArray.length > 16) {
            revert InvalidArrLength();
        }
        uint256 packedData = 0;

        for (uint256 i = 0; i < inputArray.length; i++) {
            packedData |= uint256(inputArray[i]) << (i * 16);
        }

        return packedData;
    }
}
