pragma solidity ^0.8.0;

library Util {
    function subIntFromUint(int256 a, uint256 b) public pure returns (uint256) {
        if (a < 0) {
            // If a is negative, add its absolute value to b
            return b + uint256(-a);
        } else {
            // If a is positive, subtract it from b
            require(b >= uint256(a), "negative_uint");
            return b - uint256(a);
        }
    }

    // Retrieve the nth uint16 value from a packed uint256
    function getUint16FromPacked(uint256 packedData, uint256 n) public pure returns (uint16) {
        require(n < 16, "Index out of bounds");
        uint256 shiftAmount = n * 16;
        uint16 result = uint16((packedData >> shiftAmount) & 0xFFFF);
        return result;
    }

    // Helper for creating a packed uint256 from a uint16 array
    function packUint16Array(uint16[] memory inputArray) public pure returns (uint256) {
        require(inputArray.length <= 16, "Array too long");
        uint256 packedData = 0;

        for (uint256 i = 0; i < inputArray.length; i++) {
            packedData |= uint256(inputArray[i]) << (i * 16);
        }

        return packedData;
    }
}
