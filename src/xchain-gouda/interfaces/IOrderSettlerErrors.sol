// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

/// @notice Interface for all errors in a cross-chain order settler
interface IOrderSettlerErrors {
    /// @notice Thrown when trying to initiate a settlement that's already initiated
    /// @param orderId The order hash to identify the order
    error SettlementAlreadyInitiated(bytes32 orderId);

    /// @notice Thrown when trying to perform an action on a pending settlement that's already been completed
    /// @param orderId The order hash to identify the order
    error SettlementAlreadyCompleted(bytes32 orderId);

    /// @notice Thrown when trying to cancen an order that cannot be cancelled because deadline has not passed
    /// @param orderId The order hash to identify the order
    error CannotCancelBeforeDeadline(bytes32 orderId);

    /// @notice Thrown when trying to interact with a settlement that does not exist
    /// @param orderId The order hash to identify the order of the settlement
    error SettlementDoesNotExist(bytes32 orderId);

    /// @notice Thrown when confirming outputs of an order are filled, but the amount of output tokens filled does not
    /// match the expected amount of output tokens
    error OutputsLengthMismatch(bytes32 orderId);

    /// @notice Thrown when validating a settlement fill but the recipient does not match the expected recipient
    /// @param orderId The order hash
    /// @param outputIndex The index of the invalid settlement output
    error InvalidRecipient(bytes32 orderId, uint16 outputIndex);

    /// @notice Thrown when validating a settlement fill but the token does not match the expected token
    /// @param orderId The order hash
    /// @param outputIndex The index of the invalid settlement output
    error InvalidToken(bytes32 orderId, uint16 outputIndex);

    /// @notice Thrown when validating a settlement fill but the amount does not match the expected amount
    /// @param orderId The order hash
    /// @param outputIndex The index of the invalid settlement output
    error InvalidAmount(bytes32 orderId, uint16 outputIndex);

    /// @notice Thrown when validating a settlement fill but the chainId does not match the expected chainId
    /// @param orderId The order hash
    /// @param outputIndex The index of the invalid settlement output
    error InvalidChain(bytes32 orderId, uint16 outputIndex);

    /// @notice Thrown when trying to finalize an order before the optimistic deadline period is over
    /// @param orderId The order hash
    error CannotFinalizeBeforeDeadline(bytes32 orderId);

    /// @notice Thrown when trying to challenge settlement that is already challenged or already completed
    /// @param orderId The order hash
    error CanOnlyChallengePendingSettlements(bytes32 orderId);
}
