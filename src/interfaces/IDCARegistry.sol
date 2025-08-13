// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ResolvedOrderV2} from "../base/ReactorStructs.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";

/// @notice Interface for DCA registry that tracks and validates DCA order execution
interface IDCARegistry {
    // ===== Core Structs =====

    /// @notice Public DCA intent that users sign over
    struct DCAIntent {
        address inputToken; // Token to sell
        address outputToken; // Token to buy
        address cosigner; // TEE cosigner address that will authorize executions
        uint256 minPeriod; // Minimum seconds between chunks
        uint256 maxPeriod; // Maximum seconds between chunks
        uint256 minChunkSize; // Minimum input amount per chunk
        uint256 maxChunkSize; // Maximum input amount per chunk
        uint256 minPrice; // Minimum acceptable price (outputToken/inputToken) scaled by 1e18
        uint256 deadline; // Intent expiration timestamp
        bytes32 privateIntentHash; // Hash of private parameters (total amount, exact schedule, etc)
    }

    /// @notice DCA execution state for tracking chunks
    struct DCAExecutionState {
        uint256 executedChunks; // Number of chunks executed
        uint256 lastExecutionTime; // Timestamp of last execution
        uint256 totalInputExecuted; // Total input tokens executed
        uint256 totalOutputReceived; // Total output tokens received
        bool cancelled; // Whether intent is cancelled
    }

    /// @notice Cosigner data for specific order execution
    /// @dev The cosigner enforces the minimum output amount for this chunk based on current market conditions
    struct DCAOrderCosignerData {
        address swapper; // The actual swapper (user) address
        uint256 authorizationTimestamp; // When cosigner authorizes execution
        uint256 inputAmount; // Specific input amount for this chunk
        uint256 chunkMinOutput; // Minimum output amount required for this chunk
        bytes32 orderNonce; // Unique nonce for this order execution
    }

    /// @notice DCA intent parameters encoded in preExecutionHookData
    struct DCAValidationData {
        DCAIntent intent; // The signed DCA intent
        bytes signature; // User's signature over the intent
        DCAOrderCosignerData cosignerData; // Specific order execution data
        bytes cosignature; // Cosigner's signature over (intentHash || cosignerData)
        // TODO: Remove these permit fields in refactor
        IAllowanceTransfer.PermitSingle permit; // Permit2 allowance data
        bytes permitSignature; // Signature for permit
    }

    /// @notice Parameters for updating an existing DCA intent
    struct DCAIntentUpdate {
        bytes32 intentHash; // Intent to update
        uint256 newMinPeriod; // New min period (0 = no change)
        uint256 newMaxPeriod; // New max period (0 = no change)
        uint256 newMinChunkSize; // New min chunk size (0 = no change)
        uint256 newMaxChunkSize; // New max chunk size (0 = no change)
        uint256 newMinPrice; // New min price (0 = no change)
        uint256 newDeadline; // New deadline (0 = no change)
        address newCosigner; // New cosigner (address(0) = no change)
    }

    // ===== Events =====

    /// @notice Emitted when a DCA intent is registered
    event DCAIntentRegistered(bytes32 indexed intentHash, address indexed owner, DCAIntent intent);

    /// @notice Emitted when a DCA intent is updated
    event DCAIntentUpdated(bytes32 indexed intentHash, address indexed owner, DCAIntentUpdate update);

    /// @notice Emitted when a DCA intent is cancelled
    event DCAIntentCancelled(
        bytes32 indexed intentHash, address indexed owner, uint256 totalExecuted, uint256 chunksExecuted
    );

    /// @notice Emitted when a DCA chunk is executed
    /// @dev Includes price information for transparency and analysis
    event DCAChunkExecuted( // Actual price achieved (output/input * 1e18)
        bytes32 indexed intentHash,
        uint256 chunkNumber,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 executionPrice,
        uint256 timestamp
    );

    // ===== Errors =====

    error InvalidPeriod(); // Period constraints violated
    error InvalidChunkSize(); // Chunk size out of bounds
    error PriceBelowMinimum(); // Execution price below user's minimum
    error InvalidDCAParams();
    error InvalidSignature();
    error InvalidCosignature();
    error IntentExpired();
    error IntentAlreadyRegistered();
    error IntentNotRegistered();
    error IntentCancelled();
    error OrderNonceAlreadyUsed();
    error InvalidTokens();
    error InvalidCosigner();
    error InvalidAuthorizationTimestamp();
    error UnauthorizedUpdate();
    error NoUpdateProvided();
    error InvalidPrice(); // Price calculation issues

    // ===== Intent Management Functions =====

    /// @notice Register a new DCA intent
    /// @param intent The DCA intent to register
    /// @param signature User's EIP-712 signature over the intent
    /// @return intentHash The hash of the registered intent
    function registerIntent(DCAIntent memory intent, bytes memory signature) external returns (bytes32 intentHash);

    /// @notice Update an existing DCA intent
    /// @dev Only the intent owner can update
    /// @param update The update parameters
    function updateIntent(DCAIntentUpdate memory update) external;

    /// @notice Cancel a DCA intent
    /// @dev Only the intent owner can cancel
    /// @param intentHash The intent to cancel
    function cancelIntent(bytes32 intentHash) external;

    /// @notice Cancel multiple DCA intents in one transaction
    /// @dev Only the intent owner can cancel their intents
    /// @param intentHashes Array of intent hashes to cancel
    function cancelIntents(bytes32[] memory intentHashes) external;

    // ===== View Functions =====

    /// @notice Get execution state for a DCA intent
    /// @param intentHash Hash of the DCA intent
    /// @return state The current execution state
    function getExecutionState(bytes32 intentHash) external view returns (DCAExecutionState memory state);

    /// @notice Get the intent owner
    /// @param intentHash Hash of the DCA intent
    /// @return owner The owner address
    function getIntentOwner(bytes32 intentHash) external view returns (address owner);

    /// @notice Get the registered intent
    /// @param intentHash Hash of the DCA intent
    /// @return intent The DCA intent
    function getIntent(bytes32 intentHash) external view returns (DCAIntent memory intent);

    /// @notice Check if an intent is registered and active
    /// @param intentHash Hash of the DCA intent
    /// @return isActive Whether the intent is registered and not cancelled
    function isIntentActive(bytes32 intentHash) external view returns (bool isActive);

    /// @notice Check if an order nonce has been used
    /// @param intentHash Hash of the DCA intent
    /// @param orderNonce The order nonce to check
    /// @return used Whether the nonce has been used
    function isOrderNonceUsed(bytes32 intentHash, bytes32 orderNonce) external view returns (bool used);

    /// @notice Calculate the next valid execution time for an intent
    /// @param intentHash Hash of the DCA intent
    /// @return earliestTime The earliest time the next execution can occur
    /// @return latestTime The latest time the next execution can occur (0 if no limit)
    function getNextExecutionWindow(bytes32 intentHash)
        external
        view
        returns (uint256 earliestTime, uint256 latestTime);

    /// @notice Check if an intent can be executed with given parameters
    /// @param intentHash Hash of the DCA intent
    /// @param inputAmount Proposed input amount
    /// @param outputAmount Expected output amount
    /// @return canExecute Whether execution is allowed
    /// @return reason Human-readable reason if not allowed
    function canExecute(bytes32 intentHash, uint256 inputAmount, uint256 outputAmount)
        external
        view
        returns (bool canExecute, string memory reason);

    // ===== EIP-712 Functions =====

    /// @notice Get the EIP-712 domain separator for DCA intent signing
    /// @return The domain separator hash
    function getDomainSeparator() external view returns (bytes32);

    /// @notice Hash a DCA intent for signing
    /// @param intent The DCA intent to hash
    /// @return The EIP-712 hash of the intent
    function hashDCAIntent(DCAIntent memory intent) external view returns (bytes32);

    /// @notice Hash an intent update for signing
    /// @param update The update to hash
    /// @return The EIP-712 hash of the update
    function hashIntentUpdate(DCAIntentUpdate memory update) external view returns (bytes32);

    /// @notice Hash cosigner data for a specific order
    /// @param intentHash Hash of the DCA intent
    /// @param cosignerData The cosigner data
    /// @return The hash for cosigner to sign
    function hashCosignerData(bytes32 intentHash, DCAOrderCosignerData memory cosignerData)
        external
        pure
        returns (bytes32);

    // ===== Statistics Functions =====

    /// @notice Get statistics for a DCA intent
    /// @param intentHash Hash of the DCA intent
    /// @return totalChunks Total number of chunks executed
    /// @return totalInput Total input amount executed
    /// @return totalOutput Total output amount received
    /// @return averagePrice Average execution price (output/input * 1e18)
    /// @return lastExecutionTime Timestamp of last execution
    function getIntentStatistics(bytes32 intentHash)
        external
        view
        returns (
            uint256 totalChunks,
            uint256 totalInput,
            uint256 totalOutput,
            uint256 averagePrice,
            uint256 lastExecutionTime
        );

    /// @notice Get all active intents for an owner
    /// @param owner The owner address
    /// @return intentHashes Array of active intent hashes
    function getActiveIntentsForOwner(address owner) external view returns (bytes32[] memory intentHashes);

    /// @notice Calculate the current price from amounts
    /// @dev Price = outputAmount * 1e18 / inputAmount
    /// @param inputAmount Input token amount
    /// @param outputAmount Output token amount
    /// @return price The calculated price scaled by 1e18
    function calculatePrice(uint256 inputAmount, uint256 outputAmount) external pure returns (uint256 price);

    /// @notice Check if a price meets the minimum requirement
    /// @param intentHash Hash of the DCA intent
    /// @param inputAmount Input amount for the trade
    /// @param outputAmount Output amount for the trade
    /// @return meetsRequirement Whether the price meets minimum
    /// @return actualPrice The actual price calculated
    /// @return minPrice The minimum required price
    function validatePrice(bytes32 intentHash, uint256 inputAmount, uint256 outputAmount)
        external
        view
        returns (bool meetsRequirement, uint256 actualPrice, uint256 minPrice);
}
