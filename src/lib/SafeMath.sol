pragma solidity ^0.8.0;

library SafeMath {
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
}
