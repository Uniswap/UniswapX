// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {BaseHook} from "../../../src/base/BaseHook.sol";
import {ResolvedOrderV2} from "../../../src/base/ReactorStructs.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {IPreExecutionHook} from "../../../src/interfaces/IPreExecutionHook.sol";

contract MockPreExecutionHook is BaseHook {
    error MockPreExecutionError();

    bool public isValid = true;
    mapping(address => bool) public invalidFillers; // true means invalid

    // State tracking for testing state modifications
    uint256 public preExecutionCounter;
    mapping(address => uint256) public fillerExecutions;

    constructor(IPermit2 _permit2) BaseHook(_permit2) {}

    function setValid(bool _valid) external {
        isValid = _valid;
    }

    function setFillerValid(address filler, bool valid) external {
        invalidFillers[filler] = !valid; // If valid is true, set invalidity to false
    }

    /// @notice Override the before hook to add custom validation
    function _beforeTokenTransfer(address filler, ResolvedOrderV2 calldata) internal override {
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
