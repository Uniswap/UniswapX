// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ResolvedOrder} from "../base/ReactorStructs.sol";

/// @notice Hook to be called before order execution, allowing state modifications
interface IPreExecutionHook {
    /// @notice Called by the reactor before order execution for custom validation and state changes
    /// @param filler The filler of the order
    /// @param resolvedOrder The resolved order to fill
    /// @dev This function can modify state, unlike the view-only validate function
    function preExecutionHook(address filler, ResolvedOrder calldata resolvedOrder) external;
}
    
/// @notice Hook to be called after transferring output tokens, enabling chained actions
interface IPostExecutionHook {
    /// @notice Called by the reactor after order execution for chained actions
    /// @param filler The filler of the order
    /// @param resolvedOrder The resolved order that was filled
    /// @dev This function can modify state, unlike the view-only validate function
    function postExecutionHook(address filler, ResolvedOrder calldata resolvedOrder) external;
}
