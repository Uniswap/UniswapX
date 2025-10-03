// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {DeployPermit2} from "../../../util/DeployPermit2.sol";
import {DCAHookHarness} from "./DCAHookHarness.sol";
import {IReactor} from "../../../../src/v4/interfaces/IReactor.sol";
import {DCAExecutionState, OutputAllocation} from "../../../../src/v4/hooks/dca/DCAStructs.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {IDCAHook} from "../../../../src/v4/interfaces/IDCAHook.sol";

contract DCAHookTest is Test, DeployPermit2 {
    DCAHookHarness hook;
    IPermit2 permit2;
    IReactor constant REACTOR = IReactor(address(0x2345));
    address constant SWAPPER = address(0x1234);
    uint256 constant NONCE = 0;

    // Events from IDCAHook
    event IntentCancelled(bytes32 indexed intentId, address indexed swapper);

    function setUp() public {
        permit2 = IPermit2(deployPermit2());
        hook = new DCAHookHarness(permit2, REACTOR);
        vm.warp(1 days);
    }

    // ============ computeIntentId Tests ============

    function test_computeIntentId() public view {
        // Test deterministic behavior - same inputs always produce same output
        bytes32 expectedId = keccak256(abi.encodePacked(SWAPPER, NONCE));
        bytes32 actualId1 = hook.computeIntentId(SWAPPER, NONCE);
        bytes32 actualId2 = hook.computeIntentId(SWAPPER, NONCE);

        assertEq(actualId1, expectedId, "Intent ID should match expected hash");
        assertEq(actualId1, actualId2, "Same inputs should produce same ID");

        // Test encoding consistency with different values
        address testSwapper = address(0xBEEF);
        uint256 testNonce = 42;

        bytes32 expected2 = keccak256(abi.encodePacked(testSwapper, testNonce));
        bytes32 actual2 = hook.computeIntentId(testSwapper, testNonce);

        assertEq(actual2, expected2, "Should match abi.encodePacked encoding");
    }

    // ============ getExecutionState Tests ============

    function test_getExecutionState_uninitialized() public view {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);
        DCAExecutionState memory state = hook.getExecutionState(intentId);

        assertEq(state.cancelled, false, "Cancelled should be false for uninitialized state");
        assertEq(state.executedChunks, 0, "Executed chunks should be 0 for uninitialized state");
        assertEq(state.lastExecutionTime, 0, "Last execution time should be 0 for uninitialized state");
        assertEq(state.totalInputExecuted, 0, "Total input should be 0 for uninitialized state");
        assertEq(state.totalOutput, 0, "Total output should be 0 for uninitialized state");
    }

    function test_getExecutionState_afterPackedWrite() public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);
        uint96 expectedExecutedChunks = 42;
        bool expectedCancelled = true;

        hook.__setPacked(intentId, expectedExecutedChunks, expectedCancelled);
        DCAExecutionState memory state = hook.getExecutionState(intentId);

        assertEq(state.executedChunks, expectedExecutedChunks, "Should return exact executed chunks written");
        assertEq(state.cancelled, expectedCancelled, "Should return exact cancelled flag written");
        assertEq(state.lastExecutionTime, 0, "Unwritten fields remain zero");
        assertEq(state.totalInputExecuted, 0, "Unwritten fields remain zero");
        assertEq(state.totalOutput, 0, "Unwritten fields remain zero");
    }

    function test_getExecutionState_afterExecutedMetaWrite() public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);
        uint256 expectedLastExecution = block.timestamp;

        hook.__setExecutedMeta(intentId, expectedLastExecution);
        DCAExecutionState memory state = hook.getExecutionState(intentId);

        assertEq(state.lastExecutionTime, expectedLastExecution, "Should return exact lastExecutionTime written");
        assertEq(state.executedChunks, 0, "Unwritten fields remain zero");
        assertEq(state.cancelled, false, "Unwritten fields remain false");
        assertEq(state.totalInputExecuted, 0, "Unwritten fields remain zero");
        assertEq(state.totalOutput, 0, "Unwritten fields remain zero");
    }

    function test_getExecutionState_afterTotalsWrite() public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);
        uint256 expectedInputExecuted = 1e18;
        uint256 expectedOutput = 2000e6;

        hook.__setTotals(intentId, expectedInputExecuted, expectedOutput);
        DCAExecutionState memory state = hook.getExecutionState(intentId);

        assertEq(state.totalInputExecuted, expectedInputExecuted, "Should return exact totalInputExecuted written");
        assertEq(state.totalOutput, expectedOutput, "Should return exact totalOutput written");
        assertEq(state.cancelled, false, "Unwritten fields remain false");
        assertEq(state.executedChunks, 0, "Unwritten fields remain zero");
        assertEq(state.lastExecutionTime, 0, "Unwritten fields remain zero");
    }

    function test_getExecutionState_fullStateWrite() public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);

        // Write all fields
        uint96 expectedExecutedChunks = 100;
        bool expectedCancelled = true;
        uint256 expectedLastExecution = block.timestamp - 3600;
        uint256 expectedInputExecuted = 5e18;
        uint256 expectedOutput = 10000e6;

        hook.__setPacked(intentId, expectedExecutedChunks, expectedCancelled);
        hook.__setExecutedMeta(intentId, expectedLastExecution);
        hook.__setTotals(intentId, expectedInputExecuted, expectedOutput);

        DCAExecutionState memory state = hook.getExecutionState(intentId);

        assertEq(state.cancelled, expectedCancelled, "Should return exact cancelled flag");
        assertEq(state.executedChunks, expectedExecutedChunks, "Should return exact executedChunks");
        assertEq(state.lastExecutionTime, expectedLastExecution, "Should return exact lastExecutionTime");
        assertEq(state.totalInputExecuted, expectedInputExecuted, "Should return exact totalInputExecuted");
        assertEq(state.totalOutput, expectedOutput, "Should return exact totalOutput");
    }

    function testFuzz_getExecutionState_precision(
        uint96 executedChunks,
        bool cancelled,
        uint128 lastExec,
        uint128 inputExecuted,
        uint128 output
    ) public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);

        hook.__setPacked(intentId, executedChunks, cancelled);
        hook.__setExecutedMeta(intentId, lastExec);
        hook.__setTotals(intentId, inputExecuted, output);

        DCAExecutionState memory state = hook.getExecutionState(intentId);

        assertEq(state.cancelled, cancelled, "Fuzz: cancelled precision");
        assertEq(state.executedChunks, executedChunks, "Fuzz: executedChunks precision");
        assertEq(state.lastExecutionTime, lastExec, "Fuzz: lastExecutionTime precision");
        assertEq(state.totalInputExecuted, inputExecuted, "Fuzz: totalInputExecuted precision");
        assertEq(state.totalOutput, output, "Fuzz: totalOutput precision");
    }

    // ============ getNextNonce Tests ============

    function test_getNextNonce_default() public view {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);
        uint96 nextNonce = hook.getNextNonce(intentId);
        // This should return the executed chunks, which is 0 for an uninitialized intent
        assertEq(nextNonce, 0, "Uninitialized intent should have nextNonce of 0");
    }

    function test_getNextNonce_afterSet() public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);
        uint96 expectedExecutedChunks = 5;

        hook.__setPacked(intentId, expectedExecutedChunks, false);
        uint96 nextNonce = hook.getNextNonce(intentId);

        assertEq(nextNonce, expectedExecutedChunks, "Should return the executed chunks");
    }

    function test_getNextNonce_nearMaxValue() public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);
        uint96 nearMax = type(uint96).max - 1;

        hook.__setPacked(intentId, nearMax, false);
        uint96 nextNonce = hook.getNextNonce(intentId);

        assertEq(nextNonce, nearMax, "Should handle values near uint96 max without overflow");
    }

    function test_getNextNonce_maxValue() public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);
        uint96 maxValue = type(uint96).max;

        hook.__setPacked(intentId, maxValue, false);
        uint96 nextNonce = hook.getNextNonce(intentId);

        assertEq(nextNonce, maxValue, "Should handle uint96 max value");
    }

    function test_getNextNonce_isolatedFromOtherFields() public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);
        uint96 expectedExecutedChunks = 42;

        // Set nonce with cancelled=true and set other fields
        hook.__setPacked(intentId, expectedExecutedChunks, true);
        hook.__setExecutedMeta(intentId, block.timestamp);
        hook.__setTotals(intentId, 1e18, 2000e6);

        uint96 nextNonce = hook.getNextNonce(intentId);

        assertEq(nextNonce, expectedExecutedChunks, "nextNonce should be isolated from other state modifications");
    }

    function testFuzz_getNextNonce_precision(uint96 expectedExecutedChunks) public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);

        hook.__setPacked(intentId, expectedExecutedChunks, false);
        uint96 retrievedNonce = hook.getNextNonce(intentId);

        assertEq(retrievedNonce, expectedExecutedChunks, "Should preserve exact uint96 value through storage");
    }

    // TODO: overflow nonce test when complete flow is implemented

    // ============ getIntentStatistics Tests ============

    function test_getIntentStatistics_default() public view {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);

        (uint256 totalChunks, uint256 totalInput, uint256 totalOutput, uint256 averagePrice, uint256 lastExecutionTime)
        = hook.getIntentStatistics(intentId);

        assertEq(totalChunks, 0, "Default totalChunks should be 0");
        assertEq(totalInput, 0, "Default totalInput should be 0");
        assertEq(totalOutput, 0, "Default totalOutput should be 0");
        assertEq(averagePrice, 0, "Default averagePrice should be 0");
        assertEq(lastExecutionTime, 0, "Default lastExecutionTime should be 0");
    }

    function test_getIntentStatistics_populatedValues() public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);

        uint128 expectedChunks = 10;
        bool expectedCancelled = true;
        uint256 expectedLastExec = block.timestamp - 3600;
        uint256 expectedInput = 5e18; // 5 tokens with 18 decimals
        uint256 expectedOutput = 10000e6; // 10000 tokens with 6 decimals

        hook.__setPacked(intentId, expectedChunks, expectedCancelled);
        hook.__setExecutedMeta(intentId, expectedLastExec);
        hook.__setTotals(intentId, expectedInput, expectedOutput);

        (uint256 totalChunks, uint256 totalInput, uint256 totalOutput, uint256 averagePrice, uint256 lastExecutionTime)
        = hook.getIntentStatistics(intentId);

        assertEq(totalChunks, expectedChunks, "Should return exact executedChunks");
        assertEq(totalInput, expectedInput, "Should return exact totalInputExecuted");
        assertEq(totalOutput, expectedOutput, "Should return exact totalOutput");
        assertEq(lastExecutionTime, expectedLastExec, "Should return exact lastExecutionTime");

        // averagePrice = (totalOutput * 1e18) / totalInput
        uint256 expectedPrice = Math.mulDiv(expectedOutput, 1e18, expectedInput);
        assertEq(averagePrice, expectedPrice, "averagePrice should equal (totalOutput * 1e18) / totalInput");
        assertEq(averagePrice, 2000e6, "averagePrice should be 2000e6 for this scenario");
    }

    function test_getIntentStatistics_zeroInputHandling() public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);

        // Set output but no input - edge case for division by zero
        hook.__setTotals(intentId, 0, 1000e6);

        (,, uint256 totalOutput, uint256 averagePrice,) = hook.getIntentStatistics(intentId);

        assertEq(totalOutput, 1000e6, "Should return totalOutput even with zero input");
        assertEq(averagePrice, 0, "averagePrice should be 0 when totalInput is 0");
    }

    function test_getIntentStatistics_precisionCheck() public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);

        // Test with values that require precise division
        uint256 expectedInput = 3e18; // 3 tokens
        uint256 expectedOutput = 7500e6; // 7500 tokens

        hook.__setTotals(intentId, expectedInput, expectedOutput);

        (,,, uint256 averagePrice,) = hook.getIntentStatistics(intentId);

        // averagePrice = (7500e6 * 1e18) / 3e18 = 2500e18
        uint256 expectedPrice = Math.mulDiv(expectedOutput, 1e18, expectedInput);
        assertEq(averagePrice, expectedPrice, "Should maintain precision in price calculation");
        assertEq(averagePrice, 2500e6, "averagePrice should be exactly 2500e6");
    }

    function test_getIntentStatistics_largeValues() public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);

        uint256 expectedInput = 1000000e18;
        uint256 expectedOutput = 2000000000e6;

        hook.__setTotals(intentId, expectedInput, expectedOutput);

        (,,, uint256 averagePrice,) = hook.getIntentStatistics(intentId);

        // Use Math.mulDiv for safe calculation matching implementation
        uint256 expectedPrice = Math.mulDiv(expectedOutput, 1e18, expectedInput);
        assertEq(averagePrice, expectedPrice, "Should handle large values correctly");
    }

    function test_getIntentStatistics_zeroOutput() public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);

        // Set input but no output
        hook.__setTotals(intentId, 1000e18, 0);

        (, uint256 totalInput, uint256 totalOutput, uint256 averagePrice,) = hook.getIntentStatistics(intentId);

        assertEq(totalInput, 1000e18, "Should return totalInput even with zero output");
        assertEq(totalOutput, 0, "Should return zero output");
        assertEq(averagePrice, 0, "averagePrice should be 0 when totalOutput is 0");
    }

    function test_getIntentStatistics_bothZero() public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);

        // Both input and output are zero
        hook.__setTotals(intentId, 0, 0);

        (, uint256 totalInput, uint256 totalOutput, uint256 averagePrice,) = hook.getIntentStatistics(intentId);

        assertEq(totalInput, 0, "Should return zero input");
        assertEq(totalOutput, 0, "Should return zero output");
        assertEq(averagePrice, 0, "averagePrice should be 0 when both are 0");
    }

    function test_getIntentStatistics_overflowProtection() public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);

        // Test with values that WOULD overflow with simple multiplication
        uint256 largeInput = 1e18;
        uint256 largeOutput = type(uint128).max; // This * 1e18 overflows uint256

        hook.__setTotals(intentId, largeInput, largeOutput);

        (,,, uint256 averagePrice,) = hook.getIntentStatistics(intentId);

        // Math.mulDiv should handle this without overflow
        uint256 expectedPrice = Math.mulDiv(largeOutput, 1e18, largeInput);
        assertGt(averagePrice, 0, "Should calculate price without overflow");
        assertEq(averagePrice, expectedPrice, "Should match mulDiv calculation");
    }

    function test_getIntentStatistics_actualIntermediateOverflow() public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);

        // Choose values where output * 1e18 overflows uint256, but final result fits
        // output = 2^200, input = 2^100
        // output * 1e18 = 2^200 * 10^18 ≈ 2^260 (OVERFLOWS uint256!)
        // but (output * 1e18) / input = 2^200 * 10^18 / 2^100 = 2^100 * 10^18 (fits in uint256)
        uint256 output = 1606938044258990275541962092341162602522202993782792835301376; // 2^200
        uint256 input = 1267650600228229401496703205376; // 2^100

        hook.__setTotals(intentId, input, output);

        // This should NOT revert despite intermediate overflow
        (,,, uint256 averagePrice,) = hook.getIntentStatistics(intentId);

        // Verify using Math.mulDiv
        uint256 expectedPrice = Math.mulDiv(output, 1e18, input);
        assertEq(averagePrice, expectedPrice, "Should handle intermediate overflow correctly");
        assertGt(averagePrice, 0, "Price should be greater than 0");
    }

    function test_getIntentStatistics_roundingDown() public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);

        // Test division that doesn't divide evenly: 10 / 3
        uint256 input = 3;
        uint256 output = 10;

        hook.__setTotals(intentId, input, output);

        (,,, uint256 averagePrice,) = hook.getIntentStatistics(intentId);

        // Math.mulDiv floors by default: (10 * 1e18) / 3 = 3333333333333333333.333... → 3333333333333333333
        uint256 expectedPrice = Math.mulDiv(output, 1e18, input);
        assertEq(averagePrice, expectedPrice, "Should match mulDiv result");
        assertEq(averagePrice, 3333333333333333333, "Should round down to floor");

        // Verify it's not rounding up
        assertLt(averagePrice, (output * 1e18 + input - 1) / input, "Should be less than ceiling division");
    }

    function testFuzz_getIntentStatistics_handlesIntermediateOverflow(
        uint128 totalInputExecuted,
        uint128 totalOutputAmount
    ) public {
        vm.assume(totalInputExecuted > 0);

        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);
        hook.__setTotals(intentId, totalInputExecuted, totalOutputAmount);

        // Should not revert, even though totalOutputAmount * 1e18 might overflow uint256
        (,,, uint256 averagePrice,) = hook.getIntentStatistics(intentId);

        // Verify the result is correct using mulDiv
        uint256 expectedPrice = Math.mulDiv(totalOutputAmount, 1e18, totalInputExecuted);
        assertEq(averagePrice, expectedPrice);
    }

    function testFuzz_getIntentStatistics_allFields(
        uint128 chunks,
        bool cancelled,
        uint128 lastExec,
        uint128 inputAmount,
        uint128 outputAmount
    ) public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);

        hook.__setPacked(intentId, chunks, cancelled);
        hook.__setExecutedMeta(intentId, lastExec);
        hook.__setTotals(intentId, inputAmount, outputAmount);

        (uint256 totalChunks, uint256 totalInput, uint256 totalOutput, uint256 averagePrice, uint256 lastExecutionTime)
        = hook.getIntentStatistics(intentId);

        assertEq(totalChunks, chunks, "Fuzz: totalChunks precision");
        assertEq(cancelled, cancelled, "Fuzz: cancelled precision");
        assertEq(totalInput, inputAmount, "Fuzz: totalInput precision");
        assertEq(totalOutput, outputAmount, "Fuzz: totalOutput precision");
        assertEq(lastExecutionTime, lastExec, "Fuzz: lastExecutionTime precision");

        uint256 expectedPrice = inputAmount == 0 ? 0 : Math.mulDiv(outputAmount, 1e18, inputAmount);
        assertEq(averagePrice, expectedPrice, "Fuzz: averagePrice should match formula");
    }

    function testFuzz_computeIntentId_determinism(address swapper, uint256 nonce) public view {
        // Fuzz test: verify abi.encodePacked equality for any inputs
        bytes32 expectedId = keccak256(abi.encodePacked(swapper, nonce));
        bytes32 actualId = hook.computeIntentId(swapper, nonce);
        assertEq(actualId, expectedId, "Intent ID should match abi.encodePacked for any inputs");

        // Verify determinism - calling again should produce same result
        bytes32 actualId2 = hook.computeIntentId(swapper, nonce);
        assertEq(actualId, actualId2, "Should be deterministic for fuzzed inputs");
    }

    // ============ isIntentActive Tests ============

    function test_isIntentActive_uninitialized_noConstraints() public view {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);

        // No deadline or maxPeriod => always true for uninitialized
        assertTrue(hook.isIntentActive(intentId, 0, 0), "Uninitialized with no constraints should be active");
    }

    function test_isIntentActive_uninitialized_deadlineConstraints() public view {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);

        // Future deadline => true
        uint256 futureDeadline = block.timestamp + 1000;
        assertTrue(hook.isIntentActive(intentId, 0, futureDeadline), "Should be active before deadline");

        // Past deadline => false
        uint256 pastDeadline = block.timestamp - 1;
        assertFalse(hook.isIntentActive(intentId, 0, pastDeadline), "Should be inactive after deadline");

        // Exactly at deadline
        assertTrue(hook.isIntentActive(intentId, 0, block.timestamp), "Should be active at exact deadline");
    }

    function test_isIntentActive_uninitialized_maxPeriodIgnored() public view {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);

        // maxPeriod should be ignored when executedChunks == 0
        assertTrue(hook.isIntentActive(intentId, 1, 0), "maxPeriod=1 ignored for uninitialized");
        assertTrue(hook.isIntentActive(intentId, 3600, 0), "maxPeriod=3600 ignored for uninitialized");
        assertTrue(hook.isIntentActive(intentId, type(uint256).max, 0), "maxPeriod=max ignored for uninitialized");
    }

    function test_isIntentActive_withExecutions_withinMaxPeriod() public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);

        uint256 lastExecTime = block.timestamp - 3600; // 1 hour ago
        hook.__setPacked(intentId, 1, false); // Set executedChunks to 1 so that period checks are performed
        hook.__setExecutedMeta(intentId, lastExecTime);

        // Within maxPeriod window => true
        assertTrue(hook.isIntentActive(intentId, 3601, 0), "Active when within maxPeriod by 1 second");
        assertTrue(hook.isIntentActive(intentId, 7200, 0), "Active when well within maxPeriod");
    }

    function test_isIntentActive_withExecutions_overMaxPeriod() public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);

        uint256 lastExecTime = block.timestamp - 3600; // 1 hour ago
        hook.__setPacked(intentId, 1, false); // Set executedChunks to 1 so that period checks are performed
        hook.__setExecutedMeta(intentId, lastExecTime);

        // Over maxPeriod window => false
        assertFalse(hook.isIntentActive(intentId, 3599, 0), "Inactive when over maxPeriod by 1 second");
        assertFalse(hook.isIntentActive(intentId, 1800, 0), "Inactive when well over maxPeriod");
        assertFalse(hook.isIntentActive(intentId, 1, 0), "Inactive when far over maxPeriod");
    }

    function test_isIntentActive_withExecutions_exactMaxPeriod() public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);

        uint256 lastExecTime = block.timestamp - 3600; // Exactly 1 hour ago
        hook.__setPacked(intentId, 1, false); // Set executedChunks to 1 so that period checks are performed
        hook.__setExecutedMeta(intentId, lastExecTime);

        // Exactly at maxPeriod boundary
        assertTrue(hook.isIntentActive(intentId, 3600, 0), "Active at exact maxPeriod boundary");
    }

    function test_isIntentActive_deadlineDominance() public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);

        uint256 lastExecTime = block.timestamp - 100; // Recent execution
        hook.__setExecutedMeta(intentId, lastExecTime);

        // Past deadline => false regardless of valid maxPeriod
        uint256 pastDeadline = block.timestamp - 1;
        assertFalse(hook.isIntentActive(intentId, 7200, pastDeadline), "Deadline dominates: past deadline always false");
        assertFalse(hook.isIntentActive(intentId, 0, pastDeadline), "Past deadline with maxPeriod=0 still false");
    }

    function test_isIntentActive_cancelledDominance() public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);

        // Set cancelled flag
        hook.__setPacked(intentId, 0, true);

        // Cancelled => always false regardless of other conditions
        assertFalse(hook.isIntentActive(intentId, 0, 0), "Cancelled with no constraints");
        assertFalse(hook.isIntentActive(intentId, 0, block.timestamp + 1000), "Cancelled with future deadline");
        assertFalse(hook.isIntentActive(intentId, type(uint256).max, type(uint256).max), "Cancelled with max values");

        // Even with executions and valid periods
        hook.__setExecutedMeta(intentId, block.timestamp - 100);
        assertFalse(
            hook.isIntentActive(intentId, 7200, block.timestamp + 1000), "Cancelled dominates all valid conditions"
        );
    }

    function test_isIntentActive_sentinel_maxPeriodZero() public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);

        // Set execution far in the past
        uint256 veryOldExecution = 1;
        vm.warp(1000000);
        hook.__setPacked(intentId, 1, false); // Set executedChunks to 1 so that period checks are performed
        hook.__setExecutedMeta(intentId, veryOldExecution);

        // maxPeriod = 0 => no upper bound check (sentinel value)
        assertTrue(hook.isIntentActive(intentId, 0, 0), "maxPeriod=0 disables period check");
        assertTrue(hook.isIntentActive(intentId, 0, block.timestamp + 1000), "maxPeriod=0 with future deadline");
    }

    function test_isIntentActive_sentinel_deadlineZero() public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);

        // deadline = 0 => no deadline check (sentinel value)
        assertTrue(hook.isIntentActive(intentId, 0, 0), "deadline=0 disables deadline check");

        // With executions
        hook.__setPacked(intentId, 1, false); // Set executedChunks to 1 so that period checks are performed
        hook.__setExecutedMeta(intentId, block.timestamp - 100);
        assertTrue(hook.isIntentActive(intentId, 7200, 0), "deadline=0 with valid maxPeriod");
    }

    function test_isIntentActive_priorityOrder() public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);

        // Test check priority: cancelled > deadline > executedChunks > maxPeriod

        // 1. Cancelled overrides everything
        hook.__setPacked(intentId, 0, true);
        assertFalse(hook.isIntentActive(intentId, type(uint256).max, type(uint256).max), "Cancelled checked first");

        // 2. Reset and test deadline priority
        hook.__setPacked(intentId, 0, false);
        assertFalse(hook.isIntentActive(intentId, 0, block.timestamp - 1), "Deadline checked second");

        // 3. With no executions, returns true even with maxPeriod
        assertTrue(hook.isIntentActive(intentId, 1, block.timestamp + 1000), "No executions returns true");

        // 4. With executions, maxPeriod is checked
        hook.__setPacked(intentId, 1, false); // Set executedChunks to 1 so that period checks are performed
        hook.__setExecutedMeta(intentId, block.timestamp - 3600);
        assertFalse(hook.isIntentActive(intentId, 1800, block.timestamp + 1000), "maxPeriod checked last");
    }

    function testFuzz_isIntentActive_boundaries(
        uint128 timeSinceLastExec,
        uint128 maxPeriod,
        uint128 timeUntilDeadline,
        bool cancelled,
        bool hasExecutions
    ) public {
        vm.assume(timeSinceLastExec < block.timestamp);
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);

        // Setup state
        hook.__setPacked(intentId, 0, cancelled);
        if (hasExecutions) {
            hook.__setPacked(intentId, 1, cancelled); // Set executedChunks to 1
            hook.__setExecutedMeta(intentId, block.timestamp - timeSinceLastExec);
        }

        uint256 deadline = timeUntilDeadline == 0 ? 0 : block.timestamp + timeUntilDeadline;

        bool result = hook.isIntentActive(intentId, maxPeriod, deadline);

        // Verify logic
        if (cancelled) {
            assertFalse(result, "Fuzz: cancelled always false");
        } else if (deadline != 0 && block.timestamp > deadline) {
            assertFalse(result, "Fuzz: past deadline always false");
        } else if (!hasExecutions) {
            assertTrue(result, "Fuzz: no executions always true (if not cancelled/past deadline)");
        } else if (maxPeriod != 0 && timeSinceLastExec > maxPeriod) {
            assertFalse(result, "Fuzz: over maxPeriod false");
        } else {
            assertTrue(result, "Fuzz: should be active");
        }
    }

    // ============ cancelIntent Tests ============

    function test_cancelIntent_success() public {
        uint256 nonce = 42;
        bytes32 expectedIntentId = hook.computeIntentId(SWAPPER, nonce);

        // Setup: SWAPPER calls cancelIntent
        vm.prank(SWAPPER);
        vm.expectEmit(true, true, false, true);
        emit IntentCancelled(expectedIntentId, SWAPPER);
        hook.cancelIntent(nonce);

        // Verify state changed
        DCAExecutionState memory state = hook.getExecutionState(expectedIntentId);
        assertTrue(state.cancelled, "Intent should be marked as cancelled");

        // Verify intent is inactive
        assertFalse(hook.isIntentActive(expectedIntentId, 0, 0), "Cancelled intent should be inactive");
    }

    function test_cancelIntent_onlyMsgSender() public {
        uint256 nonce = 42;
        address otherUser = address(0x9999);

        // Attempt to cancel another user's intent fails
        bytes32 swapperIntentId = hook.computeIntentId(SWAPPER, nonce);
        bytes32 otherIntentId = hook.computeIntentId(otherUser, nonce);

        // otherUser cannot cancel SWAPPER's intent (different intentId computed)
        vm.prank(otherUser);
        hook.cancelIntent(nonce); // This cancels otherUser's intent, not SWAPPER's

        // Verify SWAPPER's intent is still active
        DCAExecutionState memory swapperState = hook.getExecutionState(swapperIntentId);
        assertFalse(swapperState.cancelled, "SWAPPER's intent should not be cancelled by other user");

        // Verify otherUser's intent is cancelled
        DCAExecutionState memory otherState = hook.getExecutionState(otherIntentId);
        assertTrue(otherState.cancelled, "Other user's intent should be cancelled");
    }

    function test_cancelIntent_idempotent() public {
        uint256 nonce = 42;
        bytes32 expectedIntentId = hook.computeIntentId(SWAPPER, nonce);

        // First cancel
        vm.startPrank(SWAPPER);
        vm.expectEmit(true, true, false, true);
        emit IntentCancelled(expectedIntentId, SWAPPER);
        hook.cancelIntent(nonce);

        // Verify cancelled
        DCAExecutionState memory state1 = hook.getExecutionState(expectedIntentId);
        assertTrue(state1.cancelled, "Should be cancelled after first call");

        // Second cancel - should revert per the implementation
        vm.expectRevert(abi.encodeWithSelector(IDCAHook.IntentAlreadyCancelled.selector, expectedIntentId));
        hook.cancelIntent(nonce);

        // State remains unchanged
        DCAExecutionState memory state2 = hook.getExecutionState(expectedIntentId);
        assertTrue(state2.cancelled, "Should remain cancelled");
        vm.stopPrank();
    }

    function test_cancelIntent_differentNonces() public {
        uint256 nonce1 = 42;
        uint256 nonce2 = 43;
        bytes32 intentId1 = hook.computeIntentId(SWAPPER, nonce1);
        bytes32 intentId2 = hook.computeIntentId(SWAPPER, nonce2);

        // Cancel only first intent
        vm.prank(SWAPPER);
        hook.cancelIntent(nonce1);

        // Verify first is cancelled, second is not
        DCAExecutionState memory state1 = hook.getExecutionState(intentId1);
        DCAExecutionState memory state2 = hook.getExecutionState(intentId2);

        assertTrue(state1.cancelled, "First intent should be cancelled");
        assertFalse(state2.cancelled, "Second intent should not be cancelled");
    }

    function test_cancelIntent_withExistingState() public {
        uint256 nonce = 42;
        bytes32 intentId = hook.computeIntentId(SWAPPER, nonce);

        // Setup existing state
        hook.__setPacked(intentId, 5, false);
        hook.__setExecutedMeta(intentId, block.timestamp - 100);
        hook.__setTotals(intentId, 1e18, 2000e6);

        // Verify state before cancel
        DCAExecutionState memory stateBefore = hook.getExecutionState(intentId);
        assertEq(stateBefore.executedChunks, 5, "executedChunks should be set");
        assertFalse(stateBefore.cancelled, "Should not be cancelled yet");

        // Cancel
        vm.prank(SWAPPER);
        hook.cancelIntent(nonce);

        // Verify cancelled but other state preserved
        DCAExecutionState memory stateAfter = hook.getExecutionState(intentId);
        assertTrue(stateAfter.cancelled, "Should be cancelled");
        assertEq(stateAfter.executedChunks, 5, "executedChunks should be preserved");
        assertEq(stateAfter.totalInputExecuted, 1e18, "totalInputExecuted should be preserved");
        assertEq(stateAfter.totalOutput, 2000e6, "totalOutput should be preserved");
    }

    function test_cancelIntent_emitsCorrectEvent() public {
        uint256 nonce = 123;
        bytes32 expectedIntentId = hook.computeIntentId(SWAPPER, nonce);

        // Expect exact event parameters
        vm.prank(SWAPPER);
        vm.expectEmit(true, true, false, true);
        emit IntentCancelled(expectedIntentId, SWAPPER);
        hook.cancelIntent(nonce);
    }

    function testFuzz_cancelIntent_variousNonces(uint256 nonce) public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, nonce);

        // Cancel with fuzzed nonce
        vm.prank(SWAPPER);
        vm.expectEmit(true, true, false, true);
        emit IntentCancelled(intentId, SWAPPER);
        hook.cancelIntent(nonce);

        // Verify cancelled
        DCAExecutionState memory state = hook.getExecutionState(intentId);
        assertTrue(state.cancelled, "Fuzz: intent should be cancelled");

        // Verify idempotent revert
        vm.prank(SWAPPER);
        vm.expectRevert(abi.encodeWithSelector(IDCAHook.IntentAlreadyCancelled.selector, intentId));
        hook.cancelIntent(nonce);
    }

    function testFuzz_cancelIntent_differentSwappers(address swapper1, address swapper2, uint256 nonce) public {
        vm.assume(swapper1 != swapper2);
        vm.assume(swapper1 != address(0));
        vm.assume(swapper2 != address(0));

        bytes32 intentId1 = hook.computeIntentId(swapper1, nonce);
        bytes32 intentId2 = hook.computeIntentId(swapper2, nonce);

        // swapper1 cancels their intent
        vm.prank(swapper1);
        hook.cancelIntent(nonce);

        // Only swapper1's intent is cancelled
        DCAExecutionState memory state1 = hook.getExecutionState(intentId1);
        DCAExecutionState memory state2 = hook.getExecutionState(intentId2);

        assertTrue(state1.cancelled, "Fuzz: swapper1's intent should be cancelled");
        assertFalse(state2.cancelled, "Fuzz: swapper2's intent should not be cancelled");
    }

    // ============ cancelIntents (batch) Tests ============

    function test_cancelIntents_emptyArray() public {
        uint256[] memory nonces = new uint256[](0);

        // Empty array should succeed without doing anything
        vm.prank(SWAPPER);
        hook.cancelIntents(nonces);

        // No state changes
        bytes32 intentId = hook.computeIntentId(SWAPPER, 0);
        DCAExecutionState memory state = hook.getExecutionState(intentId);
        assertFalse(state.cancelled, "Should not cancel any intents");
    }

    function test_cancelIntents_singleIntent() public {
        uint256[] memory nonces = new uint256[](1);
        nonces[0] = 42;

        bytes32 intentId = hook.computeIntentId(SWAPPER, 42);

        // Cancel single intent via batch
        vm.prank(SWAPPER);
        vm.expectEmit(true, true, false, true);
        emit IntentCancelled(intentId, SWAPPER);
        hook.cancelIntents(nonces);

        // Verify cancelled
        DCAExecutionState memory state = hook.getExecutionState(intentId);
        assertTrue(state.cancelled, "Intent should be cancelled");
    }

    function test_cancelIntents_multipleIntents() public {
        uint256[] memory nonces = new uint256[](3);
        nonces[0] = 10;
        nonces[1] = 20;
        nonces[2] = 30;

        bytes32 intentId1 = hook.computeIntentId(SWAPPER, 10);
        bytes32 intentId2 = hook.computeIntentId(SWAPPER, 20);
        bytes32 intentId3 = hook.computeIntentId(SWAPPER, 30);

        // Expect events for all three
        vm.prank(SWAPPER);
        vm.expectEmit(true, true, false, true);
        emit IntentCancelled(intentId1, SWAPPER);
        vm.expectEmit(true, true, false, true);
        emit IntentCancelled(intentId2, SWAPPER);
        vm.expectEmit(true, true, false, true);
        emit IntentCancelled(intentId3, SWAPPER);

        hook.cancelIntents(nonces);

        // Verify all cancelled
        assertTrue(hook.getExecutionState(intentId1).cancelled, "Intent 1 should be cancelled");
        assertTrue(hook.getExecutionState(intentId2).cancelled, "Intent 2 should be cancelled");
        assertTrue(hook.getExecutionState(intentId3).cancelled, "Intent 3 should be cancelled");
    }

    function test_cancelIntents_partialRepeats_revertsAll() public {
        uint256[] memory nonces = new uint256[](5);
        nonces[0] = 10;
        nonces[1] = 20;
        nonces[2] = 10; // Repeat - will cause revert
        nonces[3] = 30;
        nonces[4] = 20; // Another repeat

        bytes32 intentId1 = hook.computeIntentId(SWAPPER, 10);
        bytes32 intentId2 = hook.computeIntentId(SWAPPER, 20);
        bytes32 intentId3 = hook.computeIntentId(SWAPPER, 30);

        // Entire transaction reverts on duplicate (first duplicate is at index 2, which is nonce 10)
        vm.prank(SWAPPER);
        vm.expectRevert(abi.encodeWithSelector(IDCAHook.IntentAlreadyCancelled.selector, intentId1));
        hook.cancelIntents(nonces);

        // Nothing was cancelled - transaction reverted
        assertFalse(hook.getExecutionState(intentId1).cancelled, "Intent 1 not cancelled due to revert");
        assertFalse(hook.getExecutionState(intentId2).cancelled, "Intent 2 not cancelled due to revert");
        assertFalse(hook.getExecutionState(intentId3).cancelled, "Intent 3 not cancelled due to revert");
    }

    function test_cancelIntents_allRepeats_revertsAll() public {
        uint256[] memory nonces = new uint256[](3);
        nonces[0] = 42;
        nonces[1] = 42; // Repeat - will cause revert
        nonces[2] = 42;

        bytes32 intentId = hook.computeIntentId(SWAPPER, 42);

        // Transaction reverts on first duplicate
        vm.prank(SWAPPER);
        vm.expectRevert(abi.encodeWithSelector(IDCAHook.IntentAlreadyCancelled.selector, intentId));
        hook.cancelIntents(nonces);

        // Nothing was cancelled - transaction reverted
        assertFalse(hook.getExecutionState(intentId).cancelled, "Intent not cancelled due to revert");
    }

    function test_cancelIntents_preCancelledInBatch_revertsAll() public {
        uint256[] memory nonces = new uint256[](3);
        nonces[0] = 100;
        nonces[1] = 101;
        nonces[2] = 102;

        bytes32 intentId1 = hook.computeIntentId(SWAPPER, 100);
        bytes32 intentId2 = hook.computeIntentId(SWAPPER, 101);
        bytes32 intentId3 = hook.computeIntentId(SWAPPER, 102);

        // Pre-cancel the middle one
        vm.prank(SWAPPER);
        hook.cancelIntent(101);
        assertTrue(hook.getExecutionState(intentId2).cancelled, "Intent 2 pre-cancelled");

        // Try to cancel all three (should fail on middle)
        vm.prank(SWAPPER);
        vm.expectRevert(abi.encodeWithSelector(IDCAHook.IntentAlreadyCancelled.selector, intentId2));
        hook.cancelIntents(nonces);

        // First and third remain uncancelled due to revert
        assertFalse(hook.getExecutionState(intentId1).cancelled, "Intent 1 not cancelled due to revert");
        assertTrue(hook.getExecutionState(intentId2).cancelled, "Intent 2 remains cancelled from before");
        assertFalse(hook.getExecutionState(intentId3).cancelled, "Intent 3 not cancelled due to revert");
    }

    function test_cancelIntents_onlyMsgSender() public {
        uint256[] memory nonces = new uint256[](2);
        nonces[0] = 50;
        nonces[1] = 51;

        address otherUser = address(0x9999);

        bytes32 swapperIntentId1 = hook.computeIntentId(SWAPPER, 50);
        bytes32 swapperIntentId2 = hook.computeIntentId(SWAPPER, 51);
        bytes32 otherIntentId1 = hook.computeIntentId(otherUser, 50);
        bytes32 otherIntentId2 = hook.computeIntentId(otherUser, 51);

        // Other user cancels their own intents (not SWAPPER's)
        vm.prank(otherUser);
        hook.cancelIntents(nonces);

        // SWAPPER's intents remain active
        assertFalse(hook.getExecutionState(swapperIntentId1).cancelled, "SWAPPER intent 1 should not be cancelled");
        assertFalse(hook.getExecutionState(swapperIntentId2).cancelled, "SWAPPER intent 2 should not be cancelled");

        // Other user's intents are cancelled
        assertTrue(hook.getExecutionState(otherIntentId1).cancelled, "Other intent 1 should be cancelled");
        assertTrue(hook.getExecutionState(otherIntentId2).cancelled, "Other intent 2 should be cancelled");
    }

    function test_cancelIntents_largeArray() public {
        uint256 count = 100;
        uint256[] memory nonces = new uint256[](count);

        // Fill array with unique nonces
        for (uint256 i = 0; i < count; i++) {
            nonces[i] = i + 1000;
        }

        // Cancel all
        vm.prank(SWAPPER);
        hook.cancelIntents(nonces);

        // Verify sampling (first, middle, last)
        bytes32 firstId = hook.computeIntentId(SWAPPER, 1000);
        bytes32 middleId = hook.computeIntentId(SWAPPER, 1050);
        bytes32 lastId = hook.computeIntentId(SWAPPER, 1099);

        assertTrue(hook.getExecutionState(firstId).cancelled, "First intent should be cancelled");
        assertTrue(hook.getExecutionState(middleId).cancelled, "Middle intent should be cancelled");
        assertTrue(hook.getExecutionState(lastId).cancelled, "Last intent should be cancelled");
    }

    function testFuzz_cancelIntents_variousSizes(uint8 size) public {
        vm.assume(size > 0 && size <= 20); // Reasonable bounds for fuzzing

        uint256[] memory nonces = new uint256[](size);
        for (uint256 i = 0; i < size; i++) {
            nonces[i] = i + 5000; // Offset to avoid collision with other tests
        }

        // Cancel all
        vm.prank(SWAPPER);
        hook.cancelIntents(nonces);

        // Verify all cancelled
        for (uint256 i = 0; i < size; i++) {
            bytes32 intentId = hook.computeIntentId(SWAPPER, nonces[i]);
            assertTrue(hook.getExecutionState(intentId).cancelled, "Fuzz: all intents should be cancelled");
        }
    }

    function testFuzz_cancelIntents_withRepeats(uint256 nonce1, uint256 nonce2) public {
        vm.assume(nonce1 != nonce2);

        uint256[] memory nonces = new uint256[](4);
        nonces[0] = nonce1;
        nonces[1] = nonce2;
        nonces[2] = nonce1; // Repeat
        nonces[3] = nonce2; // Would repeat but not reached

        bytes32 intentId1 = hook.computeIntentId(SWAPPER, nonce1);
        bytes32 intentId2 = hook.computeIntentId(SWAPPER, nonce2);

        // Should revert on first repeat - nothing gets cancelled
        vm.prank(SWAPPER);
        vm.expectRevert(abi.encodeWithSelector(IDCAHook.IntentAlreadyCancelled.selector, intentId1));
        hook.cancelIntents(nonces);

        // Nothing cancelled due to revert
        assertFalse(hook.getExecutionState(intentId1).cancelled, "Fuzz: intent1 not cancelled due to revert");
        assertFalse(hook.getExecutionState(intentId2).cancelled, "Fuzz: intent2 not cancelled due to revert");
    }

    function test_getNextNonce() public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);

        // Initially should be 0
        assertEq(hook.getNextNonce(intentId), 0, "Initial nextNonce should be 0");

        // Set nextNonce to 5 via harness
        hook.__setPacked(intentId, 5, false);

        assertEq(hook.getNextNonce(intentId), 5, "Should return stored nextNonce");
    }

    function test_getIntentStatistics_uninitialized() public view {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);

        (uint256 totalChunks, uint256 totalInput, uint256 totalOutput, uint256 averagePrice, uint256 lastExecutionTime)
        = hook.getIntentStatistics(intentId);

        assertEq(totalChunks, 0, "Uninitialized chunks should be 0");
        assertEq(totalInput, 0, "Uninitialized input should be 0");
        assertEq(totalOutput, 0, "Uninitialized output should be 0");
        assertEq(averagePrice, 0, "Average price should be 0 when no input");
        assertEq(lastExecutionTime, 0, "Uninitialized execution time should be 0");
    }

    function test_getIntentStatistics_withExecutions() public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);

        // Set up state via harness
        uint256 execTime = 1234567890;
        hook.__setPacked(intentId, 5, false);
        hook.__setExecutedMeta(intentId, execTime);
        hook.__setTotals(intentId, 1000 ether, 2000 ether);

        (uint256 totalChunks, uint256 totalInput, uint256 totalOutput, uint256 averagePrice, uint256 lastExecutionTime)
        = hook.getIntentStatistics(intentId);

        assertEq(totalChunks, 5, "Should return correct chunks");
        assertEq(totalInput, 1000 ether, "Should return correct input");
        assertEq(totalOutput, 2000 ether, "Should return correct output");
        assertEq(averagePrice, 2e18, "Average price should be 2.0 (2000/1000 * 1e18)");
        assertEq(lastExecutionTime, execTime, "Should return correct execution time");
    }

    // ========================================
    // Price Calculation Tests
    // ========================================

    function test_calculatePrice_boundaryEquality() public view {
        // Test prices at boundary values
        uint256 minPrice = 1e18; // Example min price of 1.0

        // Exactly at boundary
        uint256 inputAmount = 1e18;
        uint256 outputAmount = 1e18;
        uint256 calculatedPrice = hook.calculatePrice(inputAmount, outputAmount);
        assertEq(calculatedPrice, minPrice, "Price should equal min price at boundary");

        // Slightly above boundary
        outputAmount = 1e18 + 1;
        calculatedPrice = hook.calculatePrice(inputAmount, outputAmount);
        assertTrue(calculatedPrice > minPrice, "Price should be above min price");

        // Slightly below boundary (would fail validation)
        outputAmount = 1e18 - 1;
        calculatedPrice = hook.calculatePrice(inputAmount, outputAmount);
        assertTrue(calculatedPrice < minPrice, "Price should be below min price");
    }

    function test_calculatePrice_extremeValues() public view {
        // Test with very large values
        uint256 maxUint = type(uint256).max / 1e18; // Avoid overflow
        assertEq(hook.calculatePrice(maxUint, maxUint), 1e18, "Max values with 1:1 ratio");

        // Test with minimum non-zero values
        assertEq(hook.calculatePrice(1, 1), 1e18, "Minimum values 1:1");
        assertEq(hook.calculatePrice(1, 2), 2e18, "Minimum input with 2x output");

        // Test precision preservation
        uint256 preciseInput = 123456789;
        uint256 preciseOutput = 987654321;
        uint256 expectedPrice = (preciseOutput * 1e18) / preciseInput;
        assertEq(hook.calculatePrice(preciseInput, preciseOutput), expectedPrice, "Precise calculation");
    }

    function test_calculatePrice_zeroInputReverts() public {
        // Test that zero input always reverts
        vm.expectRevert(IDCAHook.ZeroInputAmount.selector);
        hook.calculatePrice(0, 1000);

        vm.expectRevert(IDCAHook.ZeroInputAmount.selector);
        hook.calculatePrice(0, 0);

        vm.expectRevert(IDCAHook.ZeroInputAmount.selector);
        hook.calculatePrice(0, type(uint256).max);
    }

    function test_calculatePrice_zeroOutputAllowed() public view {
        // Zero output should be allowed (though economically meaningless)
        assertEq(hook.calculatePrice(1e18, 0), 0, "Zero output should give zero price");
        assertEq(hook.calculatePrice(1, 0), 0, "Zero output with small input");
        assertEq(hook.calculatePrice(type(uint256).max / 1e18, 0), 0, "Zero output with large input");
    }

    function test_calculatePrice_noOverflowAtBoundary() public view {
        // Test values just below overflow threshold should work
        uint256 maxSafeOutput = type(uint256).max / 1e18;
        uint256 price = hook.calculatePrice(1, maxSafeOutput);
        assertEq(price, maxSafeOutput * 1e18, "Should calculate correctly at boundary");

        // With larger input, proportionally smaller output should work
        uint256 largeInput = 1e18;
        uint256 safeOutput = type(uint256).max / 1e18;
        price = hook.calculatePrice(largeInput, safeOutput);
        assertEq(price, safeOutput, "Should handle large values below overflow");
    }

    function testFuzz_calculatePrice_overflowReverts(uint256 output) public {
        vm.assume(output > type(uint256).max / 1e18);

        vm.expectRevert();
        hook.calculatePrice(1, output);
    }

    address constant OTHER = address(0xBEEF);

    function test_cancelIntent_setsCancelledAndEmits() public {
        uint256 nonce = 7;
        bytes32 intentId = hook.computeIntentId(SWAPPER, nonce);

        vm.expectEmit(true, true, false, true);
        emit IntentCancelled(intentId, SWAPPER);

        vm.prank(SWAPPER);
        hook.cancelIntent(nonce);

        DCAExecutionState memory s = hook.getExecutionState(intentId);
        assertTrue(s.cancelled, "should be cancelled");
    }

    function test_cancelIntent_revertsWhenAlreadyCancelled() public {
        uint256 nonce = 8;
        bytes32 intentId = hook.computeIntentId(SWAPPER, nonce);

        vm.prank(SWAPPER);
        hook.cancelIntent(nonce);

        vm.prank(SWAPPER);
        vm.expectRevert(abi.encodeWithSelector(IDCAHook.IntentAlreadyCancelled.selector, intentId));
        hook.cancelIntent(nonce);
    }

    function test_cancelIntents_batchSuccess() public {
        uint256[] memory nonces = new uint256[](3);
        nonces[0] = 1;
        nonces[1] = 2;
        nonces[2] = 3;

        vm.prank(SWAPPER);
        hook.cancelIntents(nonces);

        for (uint256 i = 0; i < nonces.length; i++) {
            bytes32 id = hook.computeIntentId(SWAPPER, nonces[i]);
            assertTrue(hook.getExecutionState(id).cancelled, "batch: each should be cancelled");
        }
    }

    function test_cancelIntents_duplicateInBatch_revertsAtomically() public {
        // Pre-state: nothing cancelled
        uint256[] memory nonces = new uint256[](3);
        nonces[0] = 11;
        nonces[1] = 11;
        nonces[2] = 12;

        bytes32 intentId = hook.computeIntentId(SWAPPER, 11);

        vm.prank(SWAPPER);
        vm.expectRevert(abi.encodeWithSelector(IDCAHook.IntentAlreadyCancelled.selector, intentId));
        hook.cancelIntents(nonces);

        // Atomicity: no partial writes persisted
        for (uint256 i = 0; i < nonces.length; i++) {
            bytes32 id = hook.computeIntentId(SWAPPER, nonces[i]);
            assertFalse(hook.getExecutionState(id).cancelled, "no state changes after revert");
        }
    }

    function test_cancelIntents_revertsIfOnePreCancelled_doesNotAffectOthers() public {
        // Pre-cancel one nonce in a separate tx
        vm.prank(SWAPPER);
        hook.cancelIntent(21);

        bytes32 intentId = hook.computeIntentId(SWAPPER, 21);

        uint256[] memory nonces = new uint256[](3);
        nonces[0] = 21;
        nonces[1] = 22;
        nonces[2] = 23;

        vm.prank(SWAPPER);
        vm.expectRevert(abi.encodeWithSelector(IDCAHook.IntentAlreadyCancelled.selector, intentId));
        hook.cancelIntents(nonces);

        // Pre-cancelled remains cancelled (from prior tx); others unchanged
        bytes32 id21 = hook.computeIntentId(SWAPPER, 21);
        bytes32 id22 = hook.computeIntentId(SWAPPER, 22);
        bytes32 id23 = hook.computeIntentId(SWAPPER, 23);

        assertTrue(hook.getExecutionState(id21).cancelled, "pre-cancelled persists across tx");
        assertFalse(hook.getExecutionState(id22).cancelled, "others unaffected");
        assertFalse(hook.getExecutionState(id23).cancelled, "others unaffected");
    }

    function test_cancelIntents_emptyNoop() public {
        uint256[] memory nonces = new uint256[](0);
        vm.prank(SWAPPER);
        hook.cancelIntents(nonces);
        // no revert, no state change
    }

    function test_cancelIsolationAcrossSenders() public {
        uint256 nonce = 42;

        // OTHER cancels THEIR own intent
        vm.prank(OTHER);
        hook.cancelIntent(nonce);

        bytes32 idOther = hook.computeIntentId(OTHER, nonce);
        assertTrue(hook.getExecutionState(idOther).cancelled, "other's intent cancelled");

        // SWAPPER's intent with same nonce remains not cancelled
        bytes32 idSwapper = hook.computeIntentId(SWAPPER, nonce);
        assertFalse(hook.getExecutionState(idSwapper).cancelled, "isolation across senders");
    }

    // ========================================
    // Output Allocations Tests
    // ========================================
    function test_validateOutputAllocations_validSingleRecipient() public view {
        OutputAllocation[] memory allocations = new OutputAllocation[](1);
        allocations[0] = OutputAllocation({recipient: SWAPPER, basisPoints: 10000});

        // Should not revert
        hook.validateAllocationStructure(allocations);
    }

    function test_validateOutputAllocations_validWithFees() public view {
        OutputAllocation[] memory allocations = new OutputAllocation[](2);
        allocations[0] = OutputAllocation({
            recipient: SWAPPER,
            basisPoints: 9975 // 99.75%
        });
        allocations[1] = OutputAllocation({
            recipient: address(0xFEE),
            basisPoints: 25 // 0.25% fee
        });

        // Should not revert
        hook.validateAllocationStructure(allocations);
    }

    function test_validateOutputAllocations_revertsEmptyArray() public {
        OutputAllocation[] memory allocations = new OutputAllocation[](0);

        vm.expectRevert(IDCAHook.EmptyAllocations.selector);
        hook.validateAllocationStructure(allocations);
    }

    function test_validateOutputAllocations_revertsZeroAllocation() public {
        OutputAllocation[] memory allocations = new OutputAllocation[](2);
        allocations[0] = OutputAllocation({recipient: SWAPPER, basisPoints: 10000});
        allocations[1] = OutputAllocation({
            recipient: OTHER,
            basisPoints: 0 // Invalid: zero allocation
        });

        vm.expectRevert(IDCAHook.ZeroAllocation.selector);
        hook.validateAllocationStructure(allocations);
    }

    function test_validateOutputAllocations_revertsBelow100Percent() public {
        OutputAllocation[] memory allocations = new OutputAllocation[](2);
        allocations[0] = OutputAllocation({
            recipient: SWAPPER,
            basisPoints: 4000 // 40%
        });
        allocations[1] = OutputAllocation({
            recipient: OTHER,
            basisPoints: 5999 // 59.99% - total 99.99%
        });

        vm.expectRevert(abi.encodeWithSelector(IDCAHook.AllocationsNot100Percent.selector, 9999));
        hook.validateAllocationStructure(allocations);
    }

    function test_validateOutputAllocations_revertsExceedsDuringSum() public {
        // Test that we catch overflow during intermediate sum calculation
        OutputAllocation[] memory allocations = new OutputAllocation[](3);
        allocations[0] = OutputAllocation({
            recipient: SWAPPER,
            basisPoints: 5000 // 50%
        });
        allocations[1] = OutputAllocation({
            recipient: OTHER,
            basisPoints: 4000 // 40%
        });
        allocations[2] = OutputAllocation({
            recipient: address(0x3),
            basisPoints: 1001 // 10.01% - exceeds during sum
        });

        vm.expectRevert(IDCAHook.AllocationsExceed100Percent.selector);
        hook.validateAllocationStructure(allocations);
    }

    function test_validateOutputAllocations_manyRecipients() public view {
        OutputAllocation[] memory allocations = new OutputAllocation[](10);

        for (uint256 i = 0; i < 9; i++) {
            allocations[i] = OutputAllocation({
                recipient: address(uint160(i + 1)),
                basisPoints: 1000 // 10% each
            });
        }

        allocations[9] = OutputAllocation({
            recipient: address(uint160(10)),
            basisPoints: 1000 // Last 10%
        });

        // Should not revert
        hook.validateAllocationStructure(allocations);
    }

    function testFuzz_validateOutputAllocations_validDistributions(uint8 numRecipients, uint256 seed) public view {
        vm.assume(numRecipients > 0 && numRecipients <= 10);

        OutputAllocation[] memory allocations = new OutputAllocation[](numRecipients);
        uint256 remainingBasisPoints = 10000;

        for (uint256 i = 0; i < numRecipients - 1; i++) {
            // Distribute randomly but ensure we don't exceed remaining
            uint256 maxAllocation = remainingBasisPoints / (numRecipients - i);
            uint256 allocation = (uint256(keccak256(abi.encode(seed, i))) % maxAllocation) + 1;

            allocations[i] = OutputAllocation({recipient: address(uint160(i + 1)), basisPoints: allocation});

            remainingBasisPoints -= allocation;
        }

        // Last recipient gets the remainder to ensure exactly 100%
        allocations[numRecipients - 1] =
            OutputAllocation({recipient: address(uint160(numRecipients)), basisPoints: remainingBasisPoints});

        // Should not revert for any valid distribution
        hook.validateAllocationStructure(allocations);
    }
}
