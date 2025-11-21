// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {DCAHook} from "../../../../src/v4/hooks/dca/DCAHook.sol";
import {
    DCAExecutionState,
    OutputAllocation,
    DCAIntent,
    DCAOrderCosignerData,
    PrivateIntent,
    FeedInfo,
    PermitData
} from "../../../../src/v4/hooks/dca/DCAStructs.sol";
import {ResolvedOrder} from "../../../../src/v4/base/ReactorStructs.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {IReactor} from "../../../../src/v4/interfaces/IReactor.sol";

contract DCAHookHarness is DCAHook {
    constructor(IPermit2 p, IReactor r) DCAHook(p, r) {}

    function __setPacked(bytes32 intentId, uint128 executedChunks, bool cancelled) external {
        DCAExecutionState storage s = executionStates[intentId];
        s.executedChunks = executedChunks;
        s.cancelled = cancelled;
    }

    function __setExecutedMeta(bytes32 intentId, uint120 lastExecutionTime) external {
        DCAExecutionState storage s = executionStates[intentId];
        s.lastExecutionTime = lastExecutionTime;
    }

    function __setTotals(bytes32 intentId, uint256 totalInputExecuted, uint256 totalOutput) external {
        DCAExecutionState storage s = executionStates[intentId];
        s.totalInputExecuted = totalInputExecuted;
        s.totalOutput = totalOutput;
    }

    /// @notice Exposes the internal _validateAllocationStructure function for testing
    function validateAllocationStructure(OutputAllocation[] memory outputAllocations) external pure {
        _validateAllocationStructure(outputAllocations);
    }

    /// @notice Exposes the internal _validatePriceFloor function for testing
    function validatePriceFloor(bool isExactIn, uint160 execAmount, uint160 limitAmount, uint256 minPrice)
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

    /// @notice Exposes the internal _validateChunkSize function for testing
    function validateChunkSize(DCAIntent memory intent, DCAOrderCosignerData memory cosignerData, uint256 inputAmount)
        external
        pure
    {
        _validateChunkSize(intent, cosignerData, inputAmount);
    }

    /// @notice Helper to create a basic DCA intent for testing
    function createTestIntent(address swapper, uint96 nonce, bool isExactIn, uint256 minChunk, uint256 maxChunk)
        external
        view
        returns (DCAIntent memory)
    {
        OutputAllocation[] memory allocations = new OutputAllocation[](1);
        allocations[0] = OutputAllocation({recipient: address(0x9ABC), basisPoints: 10000});

        PrivateIntent memory privateIntent = PrivateIntent({
            totalAmount: 1000e18, exactFrequency: 3600, numChunks: 10, salt: bytes32(0), oracleFeeds: new FeedInfo[](0)
        });

        return DCAIntent({
            swapper: swapper,
            nonce: nonce,
            chainId: block.chainid,
            hookAddress: address(this),
            isExactIn: isExactIn,
            inputToken: address(0xAAAA),
            outputToken: address(0xBBBB),
            cosigner: address(0x5678),
            minPeriod: 300,
            maxPeriod: 7200,
            minChunkSize: minChunk,
            maxChunkSize: maxChunk,
            minPrice: 0,
            deadline: block.timestamp + 1 days,
            outputAllocations: allocations,
            privateIntent: privateIntent
        });
    }

    /// @notice Exposes the internal _transferInputTokens function for testing
    function transferInputTokens(ResolvedOrder calldata order, address to, PermitData memory permitData) external {
        _transferInputTokens(order, to, permitData);
    }

    /// @notice Helper to create cosigner data for testing
    function createTestCosignerData(
        address swapper,
        uint96 nonce,
        uint160 execAmount,
        uint160 limitAmount,
        uint96 orderNonce
    ) external pure returns (DCAOrderCosignerData memory) {
        return DCAOrderCosignerData({
            swapper: swapper, nonce: nonce, execAmount: execAmount, orderNonce: orderNonce, limitAmount: limitAmount
        });
    }
}
