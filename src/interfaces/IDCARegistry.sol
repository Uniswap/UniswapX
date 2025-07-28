// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ResolvedOrder} from "../base/ReactorStructs.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";

/// @notice Interface for DCA registry that tracks and validates DCA order execution
interface IDCARegistry {
    /// @notice DCA execution state for tracking chunks
    struct DCAExecutionState {
        uint256 executedChunks;
        uint256 lastExecutionTime;
        uint256 totalInputExecuted;
        uint256 totalOutputReceived;
    }

    /// @notice Public DCA intent that users sign over
    struct DCAIntent {
        address inputToken; // Token to sell
        address outputToken; // Token to buy
        address cosigner; // Trusted cosigner address
        uint256 minFrequency; // Minimum time between chunks (seconds)
        uint256 maxFrequency; // Maximum time between chunks (seconds)
        uint256 minChunkSize; // Minimum input amount per chunk
        uint256 maxChunkSize; // Maximum input amount per chunk
        uint256 minOutputAmount; // Minimum output amount expected for this DCA execution
        uint256 maxSlippage; // Max slippage in basis points (10000 = 100%)
        uint256 deadline; // Intent expiration timestamp
        bytes32 privateIntentHash; // Hash of private parameters (total amount, chunks, etc)
    }

    /// @notice Cosigner data for specific order execution
    struct DCAOrderCosignerData {
        address swapper; // The actual swapper (user) address
        uint256 authorizationTimestamp; // When cosigner authorizes execution
        uint256 inputAmount; // Specific input amount for this execution
        uint256 minOutputAmount; // Minimum output amount expected
        bytes32 orderNonce; // Unique nonce for this order
    }

    /// @notice DCA intent parameters encoded in additionalValidationData
    struct DCAValidationData {
        DCAIntent intent; // The signed DCA intent
        bytes signature; // User's signature over the intent
        DCAOrderCosignerData cosignerData; // Specific order execution data
        bytes cosignature; // Cosigner's signature over (intentHash || cosignerData)
        // Permit2 AllowanceTransfer data that lets the registry pull tokens from the swapper
        IAllowanceTransfer.PermitSingle permit; // PermitSingle granting allowance to the registry
        bytes permitSignature; // Swapper's signature over the PermitSingle
    }

    /// @notice Emitted when a DCA chunk is executed
    event DCAChunkExecuted(
        bytes32 indexed dcaIntentHash, uint256 chunkNumber, uint256 inputAmount, uint256 outputAmount, uint256 timestamp
    );

    /// @notice Emitted when a DCA intent is registered
    event DCAIntentRegistered(bytes32 indexed intentHash, address indexed user, DCAIntent intent);

    /// @notice Get execution state for a DCA intent
    /// @param dcaIntentHash Hash of the DCA intent
    /// @return state The current execution state
    function getExecutionState(bytes32 dcaIntentHash) external view returns (DCAExecutionState memory state);

    /// @notice Get the EIP-712 domain separator for DCA intent signing
    /// @return The domain separator hash
    function getDomainSeparator() external view returns (bytes32);

    /// @notice Hash a DCA intent for signing
    /// @param intent The DCA intent to hash
    /// @return The EIP-712 hash of the intent
    function hashDCAIntent(DCAIntent memory intent) external view returns (bytes32);

    /// @notice Hash cosigner data for a specific order
    /// @param intentHash Hash of the DCA intent
    /// @param cosignerData The cosigner data
    /// @return The hash for cosigner to sign
    function hashCosignerData(bytes32 intentHash, DCAOrderCosignerData memory cosignerData)
        external
        pure
        returns (bytes32);
}
