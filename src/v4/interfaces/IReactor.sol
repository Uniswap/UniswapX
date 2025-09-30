// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {SignedOrder} from "../../base/ReactorStructs.sol";

/// @notice Interface for order execution reactors
interface IReactor {
    /// @notice thrown when an auction resolver is not set
    error EmptyAuctionResolver();
    /// @notice thrown when an order's nonce has already been used
    error InvalidNonce();
    /// @notice thrown when the order targets a different reactor
    error InvalidReactor();
    /// @notice thrown when the order's deadline has passed
    error DeadlinePassed();
    /// @notice thrown when a pre-execution hook is not set
    error MissingPreExecutionHook();

    /// @notice Execute a single order
    /// @param order The order definition and valid signature to execute
    function execute(SignedOrder calldata order) external payable;

    /// @notice Execute a single order using the given callback data
    /// @param order The order definition and valid signature to execute
    /// @param callbackData The callbackData to pass to the callback
    function executeWithCallback(SignedOrder calldata order, bytes calldata callbackData) external payable;

    /// @notice Execute the given orders at once
    /// @param orders The order definitions and valid signatures to execute
    function executeBatch(SignedOrder[] calldata orders) external payable;

    /// @notice Execute the given orders at once using a callback with the given callback data
    /// @param orders The order definitions and valid signatures to execute
    /// @param callbackData The callbackData to pass to the callback
    function executeBatchWithCallback(SignedOrder[] calldata orders, bytes calldata callbackData) external payable;
}
