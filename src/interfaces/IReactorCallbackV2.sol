// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ResolvedOrderV2} from "../base/ReactorStructs.sol";

/// @notice Callback for executing orders through a reactor (V2)
interface IReactorCallbackV2 {
    /// @notice Called by the reactor during order execution
    /// @param resolvedOrders The orders to execute
    /// @param callbackData The callback data
    function reactorCallback(ResolvedOrderV2[] calldata resolvedOrders, bytes calldata callbackData) external;
}
