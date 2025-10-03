// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IPreExecutionHook} from "./IHook.sol";
import {DCAExecutionState} from "../hooks/dca/DCAStructs.sol";

/// @title IDCAHook
/// @notice Interface for the DCA (Dollar-Cost Averaging) hook contract
/// @dev Extends IPreExecutionHook to enable periodic execution of DCA intents
interface IDCAHook is IPreExecutionHook {
    /// @notice Thrown when attempting to cancel an already cancelled intent
    /// @param intentId The identifier of the intent that was already cancelled
    error IntentAlreadyCancelled(bytes32 intentId);

    /// @notice Thrown when the swapper signature is invalid
    /// @param recoveredSigner The address recovered from the signature
    /// @param expectedSwapper The expected swapper address
    error InvalidSwapperSignature(address recoveredSigner, address expectedSwapper);

    /// @notice Thrown when the cosigner signature is invalid
    /// @param recoveredCosigner The address recovered from the signature
    /// @param expectedCosigner The expected cosigner address
    error InvalidCosignerSignature(address recoveredCosigner, address expectedCosigner);

    /// @notice Thrown when the cosigner data swapper doesn't match the intent swapper
    /// @param cosignerSwapper The swapper address in cosigner data
    /// @param intentSwapper The swapper address in the intent
    error CosignerSwapperMismatch(address cosignerSwapper, address intentSwapper);

    /// @notice Thrown when the cosigner data nonce doesn't match the intent nonce
    /// @param cosignerNonce The nonce in cosigner data
    /// @param intentNonce The nonce in the intent
    error CosignerNonceMismatch(uint256 cosignerNonce, uint256 intentNonce);

    /// @notice Thrown when output allocations array is empty
    error EmptyAllocations();

    /// @notice Thrown when an output allocation has zero basis points
    error ZeroAllocation();

    /// @notice Thrown when allocations sum exceeds 100% (10000 basis points)
    error AllocationsExceed100Percent();

    /// @notice Thrown when allocations don't sum to exactly 100% (10000 basis points)
    /// @param totalBasisPoints The actual sum of basis points
    error AllocationsNot100Percent(uint256 totalBasisPoints);

    /// @notice Thrown when the hook address doesn't match the expected hook
    /// @param providedHook The hook address provided in the intent
    /// @param expectedHook The expected hook address (this contract)
    error WrongHook(address providedHook, address expectedHook);

    /// @notice Thrown when the chain ID doesn't match the current chain
    /// @param providedChainId The chain ID provided in the intent
    /// @param currentChainId The current blockchain's chain ID
    error WrongChain(uint256 providedChainId, uint256 currentChainId);

    /// @notice Thrown when the swapper address doesn't match between intent and order
    /// @param orderSwapper The swapper address in the resolved order
    /// @param intentSwapper The swapper address in the intent
    error SwapperMismatch(address orderSwapper, address intentSwapper);

    /// @notice Thrown when the input token doesn't match the intent
    /// @param orderInputToken The input token in the resolved order
    /// @param intentInputToken The input token in the intent
    error WrongInputToken(address orderInputToken, address intentInputToken);

    /// @notice Thrown when an output token doesn't match the intent
    /// @param outputToken The output token in the resolved order
    /// @param expectedToken The expected output token from the intent
    error WrongOutputToken(address outputToken, address expectedToken);

    /// @notice Thrown when chunk size is below minimum allowed
    /// @param amount The actual chunk size (input for EXACT_IN, output for EXACT_OUT)
    /// @param minChunkSize The minimum allowed chunk size
    error ChunkSizeBelowMin(uint256 amount, uint256 minChunkSize);

    /// @notice Thrown when chunk size exceeds maximum allowed
    /// @param amount The actual chunk size (input for EXACT_IN, output for EXACT_OUT)
    /// @param maxChunkSize The maximum allowed chunk size
    error ChunkSizeAboveMax(uint256 amount, uint256 maxChunkSize);

    /// @notice Thrown when input amount doesn't match execAmount (EXACT_IN)
    /// @param inputAmount The input amount in the order
    /// @param execAmount The expected exec amount from cosigner data
    error InputAmountMismatch(uint256 inputAmount, uint256 execAmount);

    /// @notice Thrown when input amount is zero (EXACT_OUT)
    error ZeroInput();

    /// @notice Thrown when input exceeds cosigner's limit (EXACT_OUT)
    /// @param inputAmount The actual input amount
    /// @param limitAmount The cosigner's limit amount
    error InputAboveLimit(uint256 inputAmount, uint256 limitAmount);

    /// @notice Thrown when attempting to execute a cancelled intent
    /// @param intentId The identifier of the cancelled intent
    error IntentIsCancelled(bytes32 intentId);

    /// @notice Thrown when the intent has expired
    /// @param currentTime The current block timestamp
    /// @param deadline The intent's deadline
    error IntentExpired(uint256 currentTime, uint256 deadline);

    /// @notice Thrown when the order nonce doesn't match the expected nonce
    /// @param providedNonce The nonce provided in the cosigner data
    /// @param expectedNonce The expected next nonce for the intent
    error WrongChunkNonce(uint96 providedNonce, uint96 expectedNonce);

    /// @notice Thrown when execution is attempted too soon after the last execution
    /// @param elapsed The time elapsed since last execution
    /// @param minPeriod The minimum required period between executions
    error TooSoon(uint256 elapsed, uint256 minPeriod);

    /// @notice Thrown when execution is attempted too late after the last execution
    /// @param elapsed The time elapsed since last execution
    /// @param maxPeriod The maximum allowed period between executions
    error TooLate(uint256 elapsed, uint256 maxPeriod);

    /// @notice Thrown when the execution price is below the minimum price floor
    /// @param executionPrice The actual execution price (scaled by 1e18)
    /// @param minPrice The minimum acceptable price (scaled by 1e18)
    error PriceBelowMin(uint256 executionPrice, uint256 minPrice);

    /// @notice Thrown when output allocation doesn't match expected amount
    /// @param recipient The recipient address
    /// @param actual The actual amount allocated to the recipient
    /// @param expected The expected amount for the recipient
    error AllocationMismatch(address recipient, uint256 actual, uint256 expected);

    /// @notice Thrown when total output is insufficient (EXACT_IN)
    /// @param totalOutput The total output amount produced
    /// @param limitAmount The minimum required output amount
    error InsufficientOutput(uint256 totalOutput, uint256 limitAmount);

    /// @notice Thrown when total output doesn't match expected amount (EXACT_OUT)
    /// @param totalOutput The actual total output amount
    /// @param execAmount The expected exact output amount
    error WrongTotalOutput(uint256 totalOutput, uint256 execAmount);

    /// @notice Thrown when input amount is zero in price calculation
    error ZeroInputAmount();

    /// @notice Emitted when an intent is cancelled
    /// @param intentId The unique identifier of the intent
    /// @param swapper The address of the swapper who cancelled the intent
    event IntentCancelled(bytes32 indexed intentId, address indexed swapper);

    /// @notice Emitted when a DCA chunk is executing
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
    function isIntentActive(bytes32 intentId, uint256 maxPeriod, uint256 deadline)
        external
        view
        returns (bool active);

    /// @notice Get the next expected nonce for an intent
    /// @param intentId The unique identifier of the intent
    /// @return nextNonce The next nonce that should be used for this intent
    function getNextNonce(bytes32 intentId) external view returns (uint96 nextNonce);

    /// @notice Calculate the price ratio with 1e18 scaling
    /// @param inputAmount The input token amount
    /// @param outputAmount The output token amount
    /// @return price The scaled price (output/input * 1e18)
    function calculatePrice(uint256 inputAmount, uint256 outputAmount) external pure returns (uint256 price);

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
