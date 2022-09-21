// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {ResolvedOrder, SignedOrder} from "../lib/ReactorStructs.sol";

/// @notice Interface for order execution reactors
interface IReactor {
    /// @notice error thrown when the specified sender doesn't match the signer
    error InvalidSender();

    /// @notice Execute a single order using the given fill specification
    /// @param order The order definition and valid signature to execute
    /// @param fillContract The contract which will fill the order
    /// @param fillData The fillData to pass to the fillContract callback
    function execute(SignedOrder calldata order, address fillContract, bytes calldata fillData) external;

    /// @notice Execute the given orders at once with the specified fill specification
    /// @param orders The order definitions and valid signatures to execute
    /// @param fillContract The contract which will fill the order
    /// @param fillData The fillData to pass to the fillContract callback
    function executeBatch(SignedOrder[] calldata orders, address fillContract, bytes calldata fillData) external;

    /// @notice Resolve order-type specific requirements into a generic order with the final inputs and outputs.
    /// @param order The encoded order to resolve
    /// @return resolvedOrder generic resolved order of inputs and outputs
    /// @dev should revert on any order-type-specific validation errors
    function resolve(bytes calldata order) external view returns (ResolvedOrder memory resolvedOrder);
}
