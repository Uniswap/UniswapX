// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {ResolvedXOrder} from "../base/XReactorStructs.sol";
import {SignedOrder} from "../../base/ReactorStructs.sol";

/// @notice Interface for cross-chain order execution reactors
interface IXReactor {
    /// @notice Initiate a single order using the given fill specification
    /// @param order The cross-chain order definition and valid signature to execute
    /// @param settlmentData The settlmentData to pass to the settlement Oracle on behalf of the filler
    function initiateSettlement(SignedOrder calldata order, bytes calldata settlmentData) external;

    /// @notice Execute the given orders at once with the specified fill specification
    /// @param settlementId The id that identifies the current settlement in progress
    function finalizeSettlement(bytes32 settlementId) external;
}
