// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

interface ITryableSelfMulticall {
    /// @notice Call multiple functions in one contract call while allowing calls to succeed even if others fail.
    /// @param data An array of encoded calls to be executed in the order sent.
    /// @return failed An array with indices corresponding to the data input param. Any indices with a 0 indicate a
    /// successful transaction and any indices with 1 indicate a failed transaction.
    function multicall(bytes[] calldata data) external returns (uint8[] memory failed);
}
