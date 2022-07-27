// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {OrderExecution} from "../interfaces/ReactorStructs.sol";

/// @notice Reactor for validating and executing orders
interface IReactor {
    /// @notice Execute an OrderExecution using the specified fill strategy
    /// @param execution The order to execute and the strategy to execute it with
    function execute(OrderExecution calldata execution) external;
}
