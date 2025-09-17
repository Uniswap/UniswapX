// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IDCAHook} from "../../interfaces/IDCAHook.sol";
import {BasePreExecutionHook} from "../../base/BaseHook.sol";
import {ResolvedOrder} from "../../base/ReactorStructs.sol";
import {DCAIntent, DCAExecutionState, DCAOrderCosignerData} from "./DCAStructs.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";

/// @title DCAHook
/// @notice DCA hook implementation for UniswapX that validates and executes DCA intents
/// @dev Inherits from BasePreExecutionHook for token transfer logic
contract DCAHook is BasePreExecutionHook, IDCAHook {
    /// @notice Mapping from intentId to execution state
    /// @dev intentId is computed as keccak256(abi.encodePacked(swapper, nonce))
    mapping(bytes32 => DCAExecutionState) internal executionStates;
    
    constructor(IPermit2 _permit2) BasePreExecutionHook(_permit2) {}
    
    /// @notice Validates DCA intent and prepares for token transfer
    /// @dev Called by BasePreExecutionHook before token transfer
    /// @param filler The filler of the order
    /// @param resolvedOrder The resolved order to fill
    function _beforeTokenTransfer(address filler, ResolvedOrder calldata resolvedOrder) internal override {
        // TODO: Implement DCA validation logic
        // This is where we'll decode and validate the DCA intent
        // silence unused param warnings in placeholder stub
        filler; resolvedOrder;
    }
    
    /// @notice Hook for custom logic after token transfer
    /// @dev Called by BasePreExecutionHook after token transfer
    /// @param filler The filler of the order
    /// @param resolvedOrder The resolved order to fill
    function _afterTokenTransfer(address filler, ResolvedOrder calldata resolvedOrder) internal override {
        // TODO: Implement any post-transfer state updates if needed
        // Most DCA logic will be in _beforeTokenTransfer
        // silence unused param warnings in placeholder stub
        filler; resolvedOrder;
    }

    /// @inheritdoc IDCAHook
    function cancelIntents(uint256[] calldata nonces) external override {
        for (uint256 i = 0; i < nonces.length; i++) {
            _cancelIntent(msg.sender, nonces[i]);
        }
    }

    /// @inheritdoc IDCAHook
    function cancelIntent(uint256 nonce) external override {
        _cancelIntent(msg.sender, nonce);
    }

    function _cancelIntent(address swapper, uint256 nonce) internal {
        bytes32 intentId = keccak256(abi.encodePacked(swapper, nonce));
        require(!executionStates[intentId].cancelled, "Intent already cancelled");
        executionStates[intentId].cancelled = true;
        emit IntentCancelled(intentId, swapper);
    }

    /// @inheritdoc IDCAHook
    function computeIntentId(address swapper, uint256 nonce) external pure override returns (bytes32) {
        return keccak256(abi.encodePacked(swapper, nonce));
    }

    /// @inheritdoc IDCAHook
    function getExecutionState(bytes32 intentId) external view override returns (DCAExecutionState memory state) {
        return executionStates[intentId];
    }

    /// @inheritdoc IDCAHook
    function isIntentActive(bytes32 intentId, uint256 maxPeriod, uint256 deadline) external view override returns (bool active) {
        DCAExecutionState storage s = executionStates[intentId];
        if (s.cancelled) return false;
        if (deadline != 0 && block.timestamp > deadline) return false;
        if (s.executedChunks == 0) return true;
        if (maxPeriod != 0 && block.timestamp - s.lastExecutionTime > maxPeriod) return false;
        return true;
    }

    /// @inheritdoc IDCAHook
    function getNextNonce(bytes32 intentId) external view override returns (uint96 nextNonce) {
        return executionStates[intentId].nextNonce;
    }


    /// @inheritdoc IDCAHook
    function calculatePrice(uint256 inputAmount, uint256 outputAmount) 
        external 
        pure 
        override 
        returns (uint256 price) 
    {
        require(inputAmount != 0, "input=0");
        return (outputAmount * 1e18) / inputAmount;
    }


    /// @inheritdoc IDCAHook
    function getIntentStatistics(bytes32 intentId) 
        external 
        view 
        override 
        returns (
            uint256 totalChunks,
            uint256 totalInput,
            uint256 totalOutput,
            uint256 averagePrice,
            uint256 lastExecutionTime
        ) 
    {
        DCAExecutionState memory s = executionStates[intentId];
        totalChunks = s.executedChunks;
        totalInput = s.totalInputExecuted;
        totalOutput = s.totalOutput;
        lastExecutionTime = s.lastExecutionTime;
        averagePrice = totalInput == 0 ? 0 : (totalOutput * 1e18) / totalInput;
    }
}