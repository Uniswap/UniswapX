// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/// @notice helpers for handling FillData
library FillDataLib {
    /// @dev special fillData used to indicate a direct fill
    /// @dev direct fills transfer tokens directly from the filler to the swapper without a callback
    bytes1 constant DIRECT_FILL = 0x01;

    /// @notice return whether or not the fillData represents a direct fill
    /// @param fillData The fill data to check
    function isDirectFill(bytes calldata fillData) internal pure returns (bool) {
        return fillData.length == 1 && fillData[0] == DIRECT_FILL;
    }
}
