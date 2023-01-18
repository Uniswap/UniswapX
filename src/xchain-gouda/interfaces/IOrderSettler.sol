// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {ResolvedOrder} from "../base/SettlementStructs.sol";
import {SignedOrder} from "../../base/ReactorStructs.sol";

/// @notice Interface for cross-chain order execution reactors
interface IOrderSettler {
    /// @notice Initiate a single order settlement using the given fill specification
    /// @param order The cross-chain order definition and valid signature to execute
    function initiateSettlement(SignedOrder calldata order) external;

    /// @notice Finalize a settlement by confirming the cross-chain fill has happened and transferring input tokens and
    /// collateral to fill recipient
    /// @param settlementId The id that identifies the current settlement in progress
    function finalizeSettlement(bytes32 settlementId) external;

    /// @notice Cancels a settmentlent that was never filled after the settlement deadline. Input and collateral tokens
    /// are returned to swapper
    /// @param settlementId The id that identifies the settlement to cancel
    function cancelSettlement(bytes32 settlementId) external;
}
