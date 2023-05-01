// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {ResolvedOrder, OutputToken} from "../base/ReactorStructs.sol";

/// @notice Interface for getting fee outputs
interface IProtocolFeeController {
    /// @notice Get fee outputs for the given orders
    /// @param orders The orders to get fee outputs for
    /// @return List of list of fee outputs to append for each provided order
    function getFeeOutputs(ResolvedOrder[] memory orders) external view returns (OutputToken[][] memory);
}
