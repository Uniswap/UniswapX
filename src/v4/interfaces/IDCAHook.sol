// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IPreExecutionHook} from "./IHook.sol";
import {DCAExecutionState} from "../hooks/dca/DCAStructs.sol";

/// @title IDCAHook
/// @notice Interface for the DCA (Dollar-Cost Averaging) hook contract
/// @dev Extends IPreExecutionHook to enable periodic execution of DCA intents
interface IDCAHook is IPreExecutionHook {
    /// @notice Emitted when an intent is cancelled
    /// @param intentId The unique identifier of the intent
    /// @param swapper The address of the swapper who cancelled the intent
    event IntentCancelled(bytes32 indexed intentId, address indexed swapper);

    /// @notice Emitted when a DCA chunk is executed
    /// @param intentId The unique identifier of the intent
    /// @param execAmount The amount being executed (input for EXACT_IN, output for EXACT_OUT)
    /// @param limitAmount The limit amount (min output for EXACT_IN, max input for EXACT_OUT)
    /// @param totalInputExecuted Cumulative input amount after this execution
    /// @param totalOutput Cumulative output amount after this execution
    event ChunkExecuted(
        bytes32 indexed intentId,
        uint256 execAmount,
        uint256 limitAmount,
        uint256 totalInputExecuted,
        uint256 totalOutput
    );

    /// @notice Cancel a single DCA intent
    /// @param nonce The nonce of the intent to cancel
    /// @dev Only callable by the intent owner (verified via msg.sender and nonce)
    function cancelIntent(uint256 nonce) external;

    /// @notice Cancel multiple DCA intents in a single transaction
    /// @param nonces Array of intent nonces to cancel
    /// @dev Only callable by the intent owner for each intent (verified via msg.sender and nonces)
    function cancelIntents(uint256[] calldata nonces) external;

    /// @notice Compute the unique identifier for an intent
    /// @param swapper The address of the swapper
    /// @param nonce The nonce of the intent
    /// @return intentId The computed intent identifier
    function computeIntentId(address swapper, uint256 nonce) external pure returns (bytes32);

    /// @notice Get the execution state for a specific intent
    /// @param intentId The unique identifier of the intent
    /// @return state The execution state of the intent
    function getExecutionState(bytes32 intentId) external view returns (DCAExecutionState memory state);

    /// @notice Check if an intent is currently active (not cancelled and within period/deadline)
    /// @dev Semantics:
    /// - Uninitialized intents (no executed chunks) are considered active unless cancelled or past deadline.
    /// - maxPeriod is enforced only after the first execution; before that, it is ignored.
    /// - A maxPeriod of 0 means no upper bound; a deadline of 0 means no deadline.
    /// @param intentId The unique identifier of the intent
    /// @param maxPeriod The maximum allowed seconds since last execution (0 = no upper bound)
    /// @param deadline The intent expiration timestamp (0 = no deadline)
    /// @return active True if the intent is active, false otherwise
    function isIntentActive(bytes32 intentId, uint256 maxPeriod, uint256 deadline) external view returns (bool active);

    /// @notice Get the next expected nonce for an intent
    /// @param intentId The unique identifier of the intent
    /// @return nextNonce The next nonce that should be used for this intent
    function getNextNonce(bytes32 intentId) external view returns (uint96 nextNonce);

    /// @notice Calculate the price ratio with 1e18 scaling
    /// @param inputAmount The input token amount
    /// @param outputAmount The output token amount
    /// @return price The scaled price (output/input * 1e18)
    function calculatePrice(uint256 inputAmount, uint256 outputAmount) 
        external 
        pure 
        returns (uint256 price);

    /// @notice Get comprehensive statistics for an intent
    /// @param intentId The unique identifier of the intent
    /// @return totalChunks Number of chunks executed
    /// @return totalInput Total input amount executed
    /// @return totalOutput Total output amount received
    /// @return averagePrice Average execution price (scaled by 1e18)
    /// @return lastExecutionTime Timestamp of last execution
    function getIntentStatistics(bytes32 intentId) 
        external 
        view 
        returns (
            uint256 totalChunks,
            uint256 totalInput,
            uint256 totalOutput,
            uint256 averagePrice,
            uint256 lastExecutionTime
        );
}