pragma solidity ^0.8.0;

import {SafeCast} from "openzeppelin-contracts/utils/math/SafeCast.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";

error NegativeUint();

library MathExt {
    /// @notice Subtracts an `int256` value from a `uint256` value and returns the result.
    /// @param a The unsigned integer from which the value is subtracted.
    /// @param b The signed integer to subtract or add.
    /// @return The result of the subtraction or addition.
    /// @custom:throws NegativeUint if the subtraction would result in a negative value.
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

    /// @notice Adds a signed integer `b` to an unsigned integer `a`, ensuring the result is within the specified bounds.
    /// @param a The base unsigned integer.
    /// @param b The signed integer to be added or subtracted.
    /// @param min The minimum bound for the result.
    /// @param max The maximum bound for the result.
    /// @return r The result of the bounded addition.
    function boundedAdd(uint256 a, int256 b, uint256 min, uint256 max) internal pure returns (uint256 r) {
        r = boundedSub(a, 0 - b, min, max);
    }

    /// @notice Subtracts or adds a signed integer `b` from an unsigned integer `a`, ensuring the result is within the specified bounds.
    /// @param a The base unsigned integer.
    /// @param b The signed integer to be subtracted or added.
    /// @param min The minimum bound for the result.
    /// @param max The maximum bound for the result.
    /// @return r The result of the bounded subtraction.
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
        r = bound(r, min, max);
    }

    /// @notice Subtracts a `uint256` value `b` from another `uint256` value `a`, returning the result as an `int256`.
    /// @param a The unsigned integer to subtract from.
    /// @param b The unsigned integer to subtract.
    /// @return The result of the subtraction as a signed integer.
    function sub(uint256 a, uint256 b) internal pure returns (int256) {
        if (a < b) {
            return 0 - SafeCast.toInt256(b - a);
        } else {
            return SafeCast.toInt256(a - b);
        }
    }

    /// @notice Bounds a uint value between a minimum and maximum value.
    /// @param value The value to be bounded.
    /// @param min The minimum value allowed.
    /// @param max The maximum value allowed.
    /// @return The bounded value.
    function bound(uint256 value, uint256 min, uint256 max) internal pure returns (uint256) {
        return Math.min(Math.max(value, min), max);
    }
}
