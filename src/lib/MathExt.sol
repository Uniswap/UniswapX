pragma solidity ^0.8.0;

import {SafeCast} from "openzeppelin-contracts/utils/math/SafeCast.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";

error NegativeUint();

library MathExt {
    function sub(uint256 a, int256 b) internal pure returns (uint256) {
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

    function boundedSub(uint256 a, int256 b, uint256 min, uint256 max) internal pure returns (uint256 r) {
        if (b < 0) {
            // If b is negative, add its absolute value to a
            uint256 absB = uint256(-b);
            // would overflow
            if (type(uint256).max - absB < a) {
                return max;
            }
            r = a + absB;
        } else {
            // If b is positive, subtract it from a
            if (a < uint256(b)) {
                // cap it at min
                return min;
            }

            r = a - uint256(b);
        }
        r = Math.min(r, max);
        r = Math.max(r, min);
    }

    function sub(uint256 a, uint256 b) internal pure returns (int256) {
        if (a < b) {
            return 0 - SafeCast.toInt256(b - a);
        } else {
            return SafeCast.toInt256(a - b);
        }
    }
}
