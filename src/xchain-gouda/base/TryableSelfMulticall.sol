// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {ITryableSelfMulticall} from "../interfaces/ITryableSelfMulticall.sol";

/// @title ITryableSelfMulticall
/// @notice Enables calling multiple methods in a single call to the contract
abstract contract TryableSelfMulticall is ITryableSelfMulticall {
    /// @inheritdoc ITryableSelfMulticall
    function multicall(bytes[] calldata data) public override returns (uint8[] memory failed) {
        failed = new uint8[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            (bool success,) = address(this).delegatecall(data[i]);
            if (!success) failed[i] = 1;
        }
    }
}
