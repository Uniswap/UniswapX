// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

library ArrayBuilder {
    /// @dev Initialize a uint256[] with length `length`
    /// @param length uint256
    function init(uint256 length) internal pure returns (uint256[] memory amounts) {
        amounts = new uint256[](length);
    }

    /// @dev Initialize a uint256[][] with length `m` and `n`
    /// @param m uint256
    /// @param n uint256
    function init(uint256 m, uint256 n) internal pure returns (uint256[][] memory amounts) {
        amounts = new uint256[][](m);
        for (uint256 i = 0; i < m; ++i) {
            amounts[i] = new uint256[](n);
        }
    }

    /// @dev Fill a uint256[] with a single value
    /// @param length uint256
    /// @param amount uint256
    function fill(uint256 length, uint256 amount) internal pure returns (uint256[] memory amounts) {
        amounts = new uint256[](length);
        for (uint256 i = 0; i < length; ++i) {
            amounts[i] = amount;
        }
    }

    /// @dev Set the value at index `i` in a to b
    /// @param a uint256[][]
    /// @param i uint256
    /// @param b uint256[]
    function set(uint256[][] memory a, uint256 i, uint256[] memory b) internal pure returns (uint256[][] memory) {
        require(i < a.length, "ArrayBuilder: index out of bounds");
        a[i] = b;
        return a;
    }

    /// @dev Push a uint256 onto a uint256[]
    /// @param a uint256[]
    /// @param b uint256
    function push(uint256[] memory a, uint256 b) internal pure returns (uint256[] memory amounts) {
        amounts = new uint256[](a.length + 1);
        for (uint256 i = 0; i < a.length; ++i) {
            amounts[i] = a[i];
        }
        amounts[a.length] = b;
    }

    /// @dev Push a uint256[] onto a uint256[][]
    /// @param a uint256[][]
    /// @param b uint256[]
    function push(uint256[][] memory a, uint256[] memory b) internal pure returns (uint256[][] memory amounts) {
        amounts = new uint256[][](a.length + 1);
        for (uint256 i = 0; i < a.length; ++i) {
            amounts[i] = a[i];
        }
        amounts[a.length] = b;
    }

    /// @dev Sum the values in a uint256[]
    /// @param a uint256[]
    function sum(uint256[] memory a) internal pure returns (uint256 _sum) {
        _sum = 0;
        for (uint256 i = 0; i < a.length; ++i) {
            _sum += a[i];
        }
    }

    /// @dev Sum the values in a uint256[][]
    /// @param a uint256[][]
    function sum(uint256[][] memory a) internal pure returns (uint256 _sum) {
        _sum = 0;
        for (uint256 i = 0; i < a.length; ++i) {
            _sum += sum(a[i]);
        }
    }
}
