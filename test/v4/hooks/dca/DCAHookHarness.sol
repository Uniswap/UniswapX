// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {DCAHook} from "../../../../src/v4/hooks/dca/DCAHook.sol";
import {DCAExecutionState} from "../../../../src/v4/hooks/dca/DCAStructs.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";

contract DCAHookHarness is DCAHook {
    constructor(IPermit2 p) DCAHook(p) {}

    function __setPacked(bytes32 intentId, uint96 nextNonce, bool cancelled) external {
        DCAExecutionState storage s = executionStates[intentId];
        s.nextNonce = nextNonce;
        s.cancelled = cancelled;
    }

    function __setExecutedMeta(bytes32 intentId, uint256 executedChunks, uint256 lastExecutionTime) external {
        DCAExecutionState storage s = executionStates[intentId];
        s.executedChunks = executedChunks;
        s.lastExecutionTime = lastExecutionTime;
    }

    function __setTotals(bytes32 intentId, uint256 totalInputExecuted, uint256 totalOutput) external {
        DCAExecutionState storage s = executionStates[intentId];
        s.totalInputExecuted = totalInputExecuted;
        s.totalOutput = totalOutput;
    }
}


