// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IPreExecutionHook} from "../../../src/interfaces/IPreExecutionHook.sol";
import {ResolvedOrderV2} from "../../../src/base/ReactorStructs.sol";

/// @notice PreExecutionHook that demonstrates state modification capabilities
/// @dev This shows how preExecutionHooks can modify external state, unlike validation contracts
contract StateModifyingHook is IPreExecutionHook {
    // External state variables that can be modified
    uint256 public externalCounter;
    address public lastFiller;
    address public lastSwapper;
    
    // Events to demonstrate state changes
    event HookExecuted(address indexed filler, address indexed swapper, uint256 counter);
    
    /// @inheritdoc IPreExecutionHook
    function preExecutionHook(address filler, ResolvedOrderV2 calldata resolvedOrder) external override {
        // Modify external state - this was not possible with validation contracts
        externalCounter++;
        lastFiller = filler;
        lastSwapper = resolvedOrder.info.swapper;
        
        // Emit event
        emit HookExecuted(filler, resolvedOrder.info.swapper, externalCounter);
        
        // Could also interact with other contracts here, such as:
        // - Update a registry
        // - Mint/burn tokens
        // - Update access control lists
        // - Record metrics
        // etc.
    }
}