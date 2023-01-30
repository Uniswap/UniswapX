// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {ResolvedOrder, SettlementStatus} from "../base/SettlementStructs.sol";
import {SignedOrder} from "../../base/ReactorStructs.sol";

/// @notice Interface for cross-chain order settlers. These contracts collect escrow tokens from the swapper and filler
/// and consult an oracle to determine whether the cross-chain fill is completed within the valid fill timeframe.
interface IOrderSettler {
    /// @notice Thrown when trying to perform an action on a pending settlement that's already been completed
    /// @param currentStatus The actual status of the settlement (either Filled or Cancelled)
    error SettlementAlreadyCompleted(SettlementStatus currentStatus);

    /// @notice Thrown when validating a settlement fill but the recipient does not match the expected recipient
    /// @param settlementId The settlementId
    /// @param outputIndex The index of the invalid settlement output
    error InvalidRecipient(bytes32 settlementId, uint16 outputIndex);

    /// @notice Thrown when validating a settlement fill but the token does not match the expected token
    /// @param settlementId The settlementId
    /// @param outputIndex The index of the invalid settlement output
    error InvalidToken(bytes32 settlementId, uint16 outputIndex);

    /// @notice Thrown when validating a settlement fill but the amount does not match the expected amount
    /// @param settlementId The settlementId
    /// @param outputIndex The index of the invalid settlement output
    error InvalidAmount(bytes32 settlementId, uint16 outputIndex);

    /// @notice Thrown when validating a settlement fill but the chainId does not match the expected chainId
    /// @param settlementId The settlementId
    /// @param outputIndex The index of the invalid settlement output
    error InvalidChain(bytes32 settlementId, uint16 outputIndex);

    /// @notice Initiate a single order settlement using the given fill specification
    /// @param order The cross-chain order definition and valid signature to execute
    /// @param crossChainFiller Address reserved as the valid address to initiate the fill on the cross-chain settlementFiller
    function initiateSettlement(SignedOrder calldata order, address crossChainFiller) external;

    /// @notice Finalize a settlement by first: confirming the cross-chain fill has happened and second: transferring
    /// input tokens and collateral to the filler
    /// @param settlementId The id that identifies the current settlement in progress
    function finalizeSettlement(bytes32 settlementId) external;

    /// @notice Cancels a settmentlent that was never filled after the settlement deadline. Input and collateral tokens
    /// are returned to swapper
    /// @param settlementId The id that identifies the settlement to cancel
    function cancelSettlement(bytes32 settlementId) external;
}
