// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Output} from "./ReactorStructs.sol";

/// @notice Callback for executing orders through a reactor.
interface IReactorCallback {
    /// @notice Called by the reactor during the execution of an order
    /// @param outputs The tokens and amounts expected to be available to the reactor after the callback
    /// @param fillData The fillData specified for an order execution
    /// @dev Must have approved each token and amount in outputs to the msg.sender
    function reactorCallback(
        // TODO: maybe this should just take TokenAmount since recipient is irrelevant
        Output[] memory outputs,
        bytes memory fillData
    )
        external;
}
