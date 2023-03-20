// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

/// @notice Interface for all errors in a cross-chain order settler
interface IOrderSettlerErrors {
    /// @notice Thrown when trying to initiate a settlement that's already initiated
    error SettlementAlreadyInitiated();

    /// @notice Thrown when trying to perform an action on a pending settlement that's already been completed
    error SettlementAlreadyCompleted();

    /// @notice Thrown when trying to cancen an order that cannot be cancelled because deadline has not passed
    error CannotCancelBeforeDeadline();

    /// @notice Thrown when trying to interact with a settlement that does not exist
    error SettlementDoesNotExist();

    /// @notice Thrown when validating a settlement fill but the outputs hash doesn't match whats sent over the bridge
    error InvalidOutputs();

    /// @notice Thrown when trying to finalize an order before the optimistic deadline period is over
    error CannotFinalizeBeforeDeadline();

    /// @notice Thrown when trying to optimistically finalize a challenged settlement.
    error OptimisticFinalizationForPendingSettlementsOnly();

    /// @notice Thrown when trying to finalize an order that was filled after the fill deadline
    error OrderFillExceededDeadline();

    /// @notice Thrown when attempting to finalize (non-optimistically) a settlement from an account other then the user
    /// selected oracle
    error OnlyOracleCanFinalizeSettlement();

    /// @notice Thrown when trying to challenge a settlement that is already challenged or already completed
    error ChallengePendingSettlementsOnly();

    /// @notice Thrown when trying to challenge a settlement whose challengeDeadline has passed
    error ChallengeDeadlinePassed();

    error InvalidSettlementKey();
}
