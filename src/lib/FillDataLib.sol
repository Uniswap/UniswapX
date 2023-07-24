// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/// @notice helpers for handling FillData
library FillDataLib {
    /// @dev special fillData used to indicate that the reactor callback should be skipped
    bytes1 constant SKIP_REACTOR_CALLBACK = 0x00;

    /// @notice return whether or not the fillData represents a direct fill
    /// @param fillData The fill data to check
    function executeReactorCallback(bytes calldata fillData) internal pure returns (bool) {
        return fillData.length != 1 || fillData[0] != SKIP_REACTOR_CALLBACK;
    }
}
