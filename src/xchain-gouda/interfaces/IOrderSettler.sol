// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {ResolvedOrder} from "../base/SettlementStructs.sol";
import {SignedOrder} from "../../base/ReactorStructs.sol";

/// @notice Interface for cross-chain order execution reactors
interface IOrderSettler {
    /// @notice Initiate a single order using the given fill specification
    /// @param order The cross-chain order definition and valid signature to execute
    function initiateSettlement(SignedOrder calldata order, address fillRecipient) external;

    /// @notice Execute the given orders at once with the specified fill specification
    /// @param settlementId The id that identifies the current settlement in progress
    function finalizeSettlement(bytes32 settlementId) external;

    /// @notice Cancels a settmentlent that was never filled after the settlement deadline
    /// @param settlementId The id that identifies the settlement to cancel
    function cancelSettlement(bytes32 settlementId) external;
}
