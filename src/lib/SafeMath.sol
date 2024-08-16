pragma solidity ^0.8.0;

contract SafeMath {
    function addIntToUint(int256 a, uint256 b) public pure returns (uint256) {
        if (a < 0) {
            // If a is negative, subtract its absolute value from b
            require(b >= uint256(-a), "negative_uint");
            return b - uint256(-a);
        } else {
            // If a is positive, add it to b
            return b + uint256(a);
        }
    }
}
