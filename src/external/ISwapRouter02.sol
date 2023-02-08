// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

interface ISwapRouter02 {
    function multicall(uint256 deadline, bytes[] calldata data) external payable returns (bytes[] memory results);
}
