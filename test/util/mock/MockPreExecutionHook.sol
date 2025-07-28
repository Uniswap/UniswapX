// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IPreExecutionHook} from "../../../src/interfaces/IPreExecutionHook.sol";
import {ResolvedOrderV2} from "../../../src/base/ReactorStructs.sol";

/// @notice Mock pre-execution hook for testing, replacing the old validation contract functionality
contract MockPreExecutionHook is IPreExecutionHook {
    error MockPreExecutionError();

    bool public isValid = true;
    mapping(address => bool) public invalidFillers; // true means invalid

    // State tracking for testing state modifications
    uint256 public preExecutionCounter;
    mapping(address => uint256) public fillerExecutions;

    function setValid(bool _valid) external {
        isValid = _valid;
    }

    function setFillerValid(address filler, bool valid) external {
        invalidFillers[filler] = !valid; // If valid is true, set invalidity to false
    }

    /// @inheritdoc IPreExecutionHook
    function preExecutionHook(address filler, ResolvedOrderV2 calldata resolvedOrder) external override {
        // First check global validity
        if (!isValid) {
            revert MockPreExecutionError();
        }

        // Check filler-specific validity (reverts if filler is marked as invalid)
        if (invalidFillers[filler]) {
            revert MockPreExecutionError();
        }

        // Track state modifications (demonstrating non-view capability)
        preExecutionCounter++;
        fillerExecutions[filler]++;
    }
}
