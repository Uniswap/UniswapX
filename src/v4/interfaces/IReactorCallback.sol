// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ResolvedOrder} from "../base/ReactorStructs.sol";

/// @notice Callback for executing orders through a reactor
interface IReactorCallback {
    /// @notice Called by the reactor during order execution
    /// @param resolvedOrders The orders to execute
    /// @param callbackData The callback data
    function reactorCallback(ResolvedOrder[] calldata resolvedOrders, bytes calldata callbackData) external;
}
