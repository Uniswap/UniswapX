// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {DCAHook} from "../../../../src/v4/hooks/dca/DCAHook.sol";
import {
    DCAExecutionState,
    OutputAllocation,
    DCAIntent,
    DCAOrderCosignerData
} from "../../../../src/v4/hooks/dca/DCAStructs.sol";
import {ResolvedOrder} from "../../../../src/v4/base/ReactorStructs.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {IReactor} from "../../../../src/v4/interfaces/IReactor.sol";

contract DCAHookHarness is DCAHook {
    constructor(IPermit2 p, IReactor r) DCAHook(p, r) {}

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

    /// @notice Exposes the internal _validateAllocations function for testing
    function validateAllocationStructure(OutputAllocation[] memory outputAllocations) external pure {
        _validateAllocationStructure(outputAllocations);
    }

    /// @notice Exposes the internal _validatePriceFloor function for testing
    function validatePriceFloor(bool isExactIn, uint256 execAmount, uint256 limitAmount, uint256 minPrice)
        external
        pure
    {
        DCAIntent memory intent;
        DCAOrderCosignerData memory cd;
        intent.isExactIn = isExactIn;
        intent.minPrice = minPrice;
        cd.execAmount = execAmount;
        cd.limitAmount = limitAmount;
        _validatePriceFloor(intent, cd);
    }

    /// @notice Exposes the internal _validateStaticFields function for testing
    function validateStaticFields(DCAIntent memory intent, ResolvedOrder memory resolvedOrder) external view {
        _validateStaticFields(intent, resolvedOrder);
    }
}
