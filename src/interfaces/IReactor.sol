// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ResolvedOrder, SignedOrder} from "../lib/ReactorStructs.sol";

/// @notice Interface for order execution reactors
interface IReactor {
    /// @notice Execute a single order using the given fill specification
    /// @param order The order definition and valid signature to execute
    /// @param fillContract The contract which will fill the order
    /// @param fillData The fillData to pass alto the fillContract callback
    function execute(SignedOrder calldata order, address fillContract, bytes calldata fillData) external;

    /// @notice Execute the given orders at once with the specified fill specification
    /// @param orders The order definitions and valid signatures to execute
    /// @param fillContract The contract which will fill the order
    /// @param fillData The fillData to pass alto the fillContract callback
    function executeBatch(SignedOrder[] calldata orders, address fillContract, bytes calldata fillData) external;

    /// @notice Resolve an order-type specific order into a generic order
    /// @param order The encoded order to resolve
    /// @return resolvedOrder generic resolved order of inputs and outputs
    /// @dev should revert on any order-type-specific validation errors
    function resolve(bytes calldata order) external view returns (ResolvedOrder memory resolvedOrder);
}
