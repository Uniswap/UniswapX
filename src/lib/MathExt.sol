pragma solidity ^0.8.0;

error NegativeUint();

function sub(uint256 a, int256 b) pure returns (uint256) {
    if (b < 0) {
        // If b is negative, add its absolute value to a
        return a + uint256(-b);
    } else {
        // If b is positive, subtract it from a
        if (a < uint256(b)) {
            revert NegativeUint();
        }

        return a - uint256(b);
    }
}
