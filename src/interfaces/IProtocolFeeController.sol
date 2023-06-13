// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ResolvedOrder, OutputToken} from "../base/ReactorStructs.sol";

/// @notice Interface for getting fee outputs
interface IProtocolFeeController {
    /// @notice Get fee outputs for the given orders
    /// @param order The orders to get fee outputs for
    /// @return List of fee outputs to append for each provided order
    function getFeeOutputs(ResolvedOrder memory order) external view returns (OutputToken[] memory);
}
