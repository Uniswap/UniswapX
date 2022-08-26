// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ResolvedOrder} from "./ReactorStructs.sol";

/// @notice Callback for executing orders through a reactor.
interface IReactorCallback {
    /// @notice Called by the reactor during the execution of an order
    /// @param resolvedOrders Has inputs and outputs
    /// @param fillData The fillData specified for an order execution
    /// @dev Must have approved each token and amount in outputs to the msg.sender
    function reactorCallback(
        // TODO: maybe this should just take TokenAmount since recipient is irrelevant
        ResolvedOrder[] memory resolvedOrders,
        bytes memory fillData
    )
        external;
}
