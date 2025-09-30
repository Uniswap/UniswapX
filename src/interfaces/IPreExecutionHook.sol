// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ResolvedOrderV2} from "../base/ReactorStructs.sol";

/// @notice Hook to be called before order execution, allowing state modifications
interface IPreExecutionHook {
    /// @notice Called by the reactor before order execution for custom validation and state changes
    /// @param filler The filler of the order
    /// @param resolvedOrder The resolved order to fill
    /// @dev This function can modify state, unlike the view-only validate function
    function preExecutionHook(address filler, ResolvedOrderV2 calldata resolvedOrder) external;
}
