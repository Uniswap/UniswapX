// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {DeployPermit2} from "../../../util/DeployPermit2.sol";
import {DCAHookHarness} from "./DCAHookHarness.sol";
import {DCAExecutionState, OutputAllocation} from "../../../../src/v4/hooks/dca/DCAStructs.sol";

contract DCAHookTest is Test, DeployPermit2 {
    DCAHookHarness hook;
    IPermit2 permit2;
    
    address constant SWAPPER = address(0x1234);
    uint256 constant NONCE = 0;
    
    function setUp() public {
        permit2 = IPermit2(deployPermit2());
        hook = new DCAHookHarness(permit2);
        vm.warp(1 days);
    }
    
    // ============ computeIntentId Tests ============

    function test_computeIntentId() public {
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
    
    function test_getExecutionState_uninitialized() public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);
        DCAExecutionState memory state = hook.getExecutionState(intentId);
        
        assertEq(state.nextNonce, 0, "Next nonce should be 0 for uninitialized state");
        assertEq(state.cancelled, false, "Cancelled should be false for uninitialized state");
        assertEq(state.executedChunks, 0, "Executed chunks should be 0 for uninitialized state");
        assertEq(state.lastExecutionTime, 0, "Last execution time should be 0 for uninitialized state");
        assertEq(state.totalInputExecuted, 0, "Total input should be 0 for uninitialized state");
        assertEq(state.totalOutput, 0, "Total output should be 0 for uninitialized state");
    }
    
    function test_getExecutionState_afterPackedWrite() public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);
        uint96 expectedNonce = 42;
        bool expectedCancelled = true;
        
        hook.__setPacked(intentId, expectedNonce, expectedCancelled);
        DCAExecutionState memory state = hook.getExecutionState(intentId);
        
        assertEq(state.nextNonce, expectedNonce, "Should return exact nextNonce written");
        assertEq(state.cancelled, expectedCancelled, "Should return exact cancelled flag written");
        assertEq(state.executedChunks, 0, "Unwritten fields remain zero");
        assertEq(state.lastExecutionTime, 0, "Unwritten fields remain zero");
        assertEq(state.totalInputExecuted, 0, "Unwritten fields remain zero");
        assertEq(state.totalOutput, 0, "Unwritten fields remain zero");
    }
    
    function test_getExecutionState_afterExecutedMetaWrite() public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);
        uint256 expectedChunks = 5;
        uint256 expectedLastExecution = block.timestamp;
        
        hook.__setExecutedMeta(intentId, expectedChunks, expectedLastExecution);
        DCAExecutionState memory state = hook.getExecutionState(intentId);
        
        assertEq(state.executedChunks, expectedChunks, "Should return exact executedChunks written");
        assertEq(state.lastExecutionTime, expectedLastExecution, "Should return exact lastExecutionTime written");
        assertEq(state.nextNonce, 0, "Unwritten fields remain zero");
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
        assertEq(state.nextNonce, 0, "Unwritten fields remain zero");
        assertEq(state.cancelled, false, "Unwritten fields remain false");
        assertEq(state.executedChunks, 0, "Unwritten fields remain zero");
        assertEq(state.lastExecutionTime, 0, "Unwritten fields remain zero");
    }
    
    function test_getExecutionState_fullStateWrite() public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);
        
        // Write all fields
        uint96 expectedNonce = 100;
        bool expectedCancelled = true;
        uint256 expectedChunks = 10;
        uint256 expectedLastExecution = block.timestamp - 3600;
        uint256 expectedInputExecuted = 5e18;
        uint256 expectedOutput = 10000e6;
        
        hook.__setPacked(intentId, expectedNonce, expectedCancelled);
        hook.__setExecutedMeta(intentId, expectedChunks, expectedLastExecution);
        hook.__setTotals(intentId, expectedInputExecuted, expectedOutput);
        
        DCAExecutionState memory state = hook.getExecutionState(intentId);
        
        assertEq(state.nextNonce, expectedNonce, "Should return exact nextNonce");
        assertEq(state.cancelled, expectedCancelled, "Should return exact cancelled flag");
        assertEq(state.executedChunks, expectedChunks, "Should return exact executedChunks");
        assertEq(state.lastExecutionTime, expectedLastExecution, "Should return exact lastExecutionTime");
        assertEq(state.totalInputExecuted, expectedInputExecuted, "Should return exact totalInputExecuted");
        assertEq(state.totalOutput, expectedOutput, "Should return exact totalOutput");
    }
    
    function testFuzz_getExecutionState_precision(
        uint96 nonce,
        bool cancelled,
        uint128 chunks,
        uint128 lastExec,
        uint128 inputExecuted,
        uint128 output
    ) public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);
        
        hook.__setPacked(intentId, nonce, cancelled);
        hook.__setExecutedMeta(intentId, chunks, lastExec);
        hook.__setTotals(intentId, inputExecuted, output);
        
        DCAExecutionState memory state = hook.getExecutionState(intentId);
        
        assertEq(state.nextNonce, nonce, "Fuzz: nextNonce precision");
        assertEq(state.cancelled, cancelled, "Fuzz: cancelled precision");
        assertEq(state.executedChunks, chunks, "Fuzz: executedChunks precision");
        assertEq(state.lastExecutionTime, lastExec, "Fuzz: lastExecutionTime precision");
        assertEq(state.totalInputExecuted, inputExecuted, "Fuzz: totalInputExecuted precision");
        assertEq(state.totalOutput, output, "Fuzz: totalOutput precision");
    }
    
    // ============ getNextNonce Tests ============
    
    function test_getNextNonce_default() public view {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);
        uint96 nextNonce = hook.getNextNonce(intentId);
        assertEq(nextNonce, 0, "Uninitialized intent should have nextNonce of 0");
    }
    
    function test_getNextNonce_afterSet() public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);
        uint96 expectedNonce = 5;
        
        hook.__setPacked(intentId, expectedNonce, false);
        uint96 nextNonce = hook.getNextNonce(intentId);
        
        assertEq(nextNonce, expectedNonce, "Should return exact value set via harness");
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
        uint96 expectedNonce = 42;
        
        // Set nonce with cancelled=true and set other fields
        hook.__setPacked(intentId, expectedNonce, true);
        hook.__setExecutedMeta(intentId, 999, block.timestamp);
        hook.__setTotals(intentId, 1e18, 2000e6);
        
        uint96 nextNonce = hook.getNextNonce(intentId);
        
        assertEq(nextNonce, expectedNonce, "nextNonce should be isolated from other state modifications");
    }
    
    function testFuzz_getNextNonce_precision(uint96 nonce) public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);
        
        hook.__setPacked(intentId, nonce, false);
        uint96 retrievedNonce = hook.getNextNonce(intentId);
        
        assertEq(retrievedNonce, nonce, "Should preserve exact uint96 value through storage");
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
        
        uint256 expectedChunks = 10;
        uint256 expectedLastExec = block.timestamp - 3600;
        uint256 expectedInput = 5e18; // 5 tokens with 18 decimals
        uint256 expectedOutput = 10000e6; // 10000 tokens with 6 decimals
        
        hook.__setExecutedMeta(intentId, expectedChunks, expectedLastExec);
        hook.__setTotals(intentId, expectedInput, expectedOutput);
        
        (uint256 totalChunks, uint256 totalInput, uint256 totalOutput, uint256 averagePrice, uint256 lastExecutionTime) 
            = hook.getIntentStatistics(intentId);
        
        assertEq(totalChunks, expectedChunks, "Should return exact executedChunks");
        assertEq(totalInput, expectedInput, "Should return exact totalInputExecuted");
        assertEq(totalOutput, expectedOutput, "Should return exact totalOutput");
        assertEq(lastExecutionTime, expectedLastExec, "Should return exact lastExecutionTime");
        
        // averagePrice = (totalOutput * 1e18) / totalInput
        uint256 expectedPrice = (expectedOutput * 1e18) / expectedInput;
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
        uint256 expectedPrice = (expectedOutput * 1e18) / expectedInput;
        assertEq(averagePrice, expectedPrice, "Should maintain precision in price calculation");
        assertEq(averagePrice, 2500e6, "averagePrice should be exactly 2500e6");
    }
    
    function test_getIntentStatistics_largeValues() public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);
        
        // Test with large but safe values
        uint256 expectedInput = 1000000e18; // 1 million tokens
        uint256 expectedOutput = 2000000000e6; // 2 billion tokens
        
        hook.__setTotals(intentId, expectedInput, expectedOutput);
        
        (,,, uint256 averagePrice,) = hook.getIntentStatistics(intentId);
        
        uint256 expectedPrice = (expectedOutput * 1e18) / expectedInput;
        assertEq(averagePrice, expectedPrice, "Should handle large values correctly");
        assertEq(averagePrice, 2000e6, "averagePrice should be 2000e6 for large values");
    }
    
    function testFuzz_getIntentStatistics_priceMath(
        uint128 totalInputExecuted,
        uint128 totalOutputAmount
    ) public {
        vm.assume(totalInputExecuted > 0); // Avoid division by zero
        
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);
        hook.__setTotals(intentId, totalInputExecuted, totalOutputAmount);
        
        (,, uint256 totalOutput, uint256 averagePrice,) = hook.getIntentStatistics(intentId);
        
        uint256 expectedPrice = (uint256(totalOutputAmount) * 1e18) / uint256(totalInputExecuted);
        assertEq(averagePrice, expectedPrice, "Fuzz: averagePrice calculation should be exact");
        assertEq(totalOutput, totalOutputAmount, "Fuzz: totalOutput should match input");
    }
    
    function testFuzz_getIntentStatistics_allFields(
        uint128 chunks,
        uint128 lastExec,
        uint128 inputAmount,
        uint128 outputAmount
    ) public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);
        
        hook.__setExecutedMeta(intentId, chunks, lastExec);
        hook.__setTotals(intentId, inputAmount, outputAmount);
        
        (uint256 totalChunks, uint256 totalInput, uint256 totalOutput, uint256 averagePrice, uint256 lastExecutionTime) 
            = hook.getIntentStatistics(intentId);
        
        assertEq(totalChunks, chunks, "Fuzz: totalChunks precision");
        assertEq(totalInput, inputAmount, "Fuzz: totalInput precision");
        assertEq(totalOutput, outputAmount, "Fuzz: totalOutput precision");
        assertEq(lastExecutionTime, lastExec, "Fuzz: lastExecutionTime precision");
        
        uint256 expectedPrice = inputAmount == 0 ? 0 : (uint256(outputAmount) * 1e18) / uint256(inputAmount);
        assertEq(averagePrice, expectedPrice, "Fuzz: averagePrice should match formula");
    }
    
    function testFuzz_computeIntentId_determinism(address swapper, uint256 nonce) public {
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
        hook.__setExecutedMeta(intentId, 1, lastExecTime);
        
        // Within maxPeriod window => true
        assertTrue(hook.isIntentActive(intentId, 3601, 0), "Active when within maxPeriod by 1 second");
        assertTrue(hook.isIntentActive(intentId, 7200, 0), "Active when well within maxPeriod");
    }
    
    function test_isIntentActive_withExecutions_overMaxPeriod() public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);
        
        uint256 lastExecTime = block.timestamp - 3600; // 1 hour ago
        hook.__setExecutedMeta(intentId, 1, lastExecTime);
        
        // Over maxPeriod window => false
        assertFalse(hook.isIntentActive(intentId, 3599, 0), "Inactive when over maxPeriod by 1 second");
        assertFalse(hook.isIntentActive(intentId, 1800, 0), "Inactive when well over maxPeriod");
        assertFalse(hook.isIntentActive(intentId, 1, 0), "Inactive when far over maxPeriod");
    }
    
    function test_isIntentActive_withExecutions_exactMaxPeriod() public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);
        
        uint256 lastExecTime = block.timestamp - 3600; // Exactly 1 hour ago
        hook.__setExecutedMeta(intentId, 1, lastExecTime);
        
        // Exactly at maxPeriod boundary
        assertTrue(hook.isIntentActive(intentId, 3600, 0), "Active at exact maxPeriod boundary");
    }
    
    function test_isIntentActive_deadlineDominance() public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);
        
        uint256 lastExecTime = block.timestamp - 100; // Recent execution
        hook.__setExecutedMeta(intentId, 1, lastExecTime);
        
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
        hook.__setExecutedMeta(intentId, 1, block.timestamp - 100);
        assertFalse(hook.isIntentActive(intentId, 7200, block.timestamp + 1000), "Cancelled dominates all valid conditions");
    }
    
    function test_isIntentActive_sentinel_maxPeriodZero() public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);
        
        // Set execution far in the past
        uint256 veryOldExecution = 1;
        vm.warp(1000000);
        hook.__setExecutedMeta(intentId, 1, veryOldExecution);
        
        // maxPeriod = 0 => no upper bound check (sentinel value)
        assertTrue(hook.isIntentActive(intentId, 0, 0), "maxPeriod=0 disables period check");
        assertTrue(hook.isIntentActive(intentId, 0, block.timestamp + 1000), "maxPeriod=0 with future deadline");
    }
    
    function test_isIntentActive_sentinel_deadlineZero() public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);
        
        // deadline = 0 => no deadline check (sentinel value)
        assertTrue(hook.isIntentActive(intentId, 0, 0), "deadline=0 disables deadline check");
        
        // With executions
        hook.__setExecutedMeta(intentId, 1, block.timestamp - 100);
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
        hook.__setExecutedMeta(intentId, 1, block.timestamp - 3600);
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
            hook.__setExecutedMeta(intentId, 1, block.timestamp - timeSinceLastExec);
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
        hook.__setExecutedMeta(intentId, 5, execTime);
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
        vm.expectRevert("input=0");
        hook.calculatePrice(0, 1000);
        
        vm.expectRevert("input=0");
        hook.calculatePrice(0, 0);
        
        vm.expectRevert("input=0");
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

    event IntentCancelled(bytes32 indexed intentId, address indexed swapper);

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

        vm.prank(SWAPPER);
        hook.cancelIntent(nonce);

        vm.prank(SWAPPER);
        vm.expectRevert("Intent already cancelled");
        hook.cancelIntent(nonce);
    }

    function test_cancelIntents_batchSuccess() public {
        uint256[] memory nonces = new uint256[](3);
        nonces[0] = 1; nonces[1] = 2; nonces[2] = 3;

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
        nonces[0] = 11; nonces[1] = 11; nonces[2] = 12;

        vm.prank(SWAPPER);
        vm.expectRevert("Intent already cancelled");
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

        uint256[] memory nonces = new uint256[](3);
        nonces[0] = 21; nonces[1] = 22; nonces[2] = 23;

        vm.prank(SWAPPER);
        vm.expectRevert("Intent already cancelled");
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

    // OutputAllocation Validation Tests
    function test_validateOutputAllocations_validSingleRecipient() public {
        OutputAllocation[] memory allocations = new OutputAllocation[](1);
        allocations[0] = OutputAllocation({
            recipient: SWAPPER,
            basisPoints: 10000
        });
        
        // Should not revert
        hook.validateOutputAllocations(allocations);
    }


    function test_validateOutputAllocations_validMultipleRecipients() public {
        OutputAllocation[] memory allocations = new OutputAllocation[](3);
        allocations[0] = OutputAllocation({
            recipient: SWAPPER,
            basisPoints: 5000  // 50%
        });
        allocations[1] = OutputAllocation({
            recipient: OTHER,
            basisPoints: 3000  // 30%
        });
        allocations[2] = OutputAllocation({
            recipient: address(0xFEE),
            basisPoints: 2000  // 20%
        });
        
        // Should not revert
        hook.validateOutputAllocations(allocations);
    }

    function test_validateOutputAllocations_validWithFees() public {
        OutputAllocation[] memory allocations = new OutputAllocation[](2);
        allocations[0] = OutputAllocation({
            recipient: SWAPPER,
            basisPoints: 9975  // 99.75%
        });
        allocations[1] = OutputAllocation({
            recipient: address(0xFEE),
            basisPoints: 25    // 0.25% fee
        });
        
        // Should not revert
        hook.validateOutputAllocations(allocations);
    }

    function test_validateOutputAllocations_revertsEmptyArray() public {
        OutputAllocation[] memory allocations = new OutputAllocation[](0);
        
        vm.expectRevert("Empty allocations");
        hook.validateOutputAllocations(allocations);
    }

    function test_validateOutputAllocations_revertsZeroAllocation() public {
        OutputAllocation[] memory allocations = new OutputAllocation[](2);
        allocations[0] = OutputAllocation({
            recipient: SWAPPER,
            basisPoints: 10000
        });
        allocations[1] = OutputAllocation({
            recipient: OTHER,
            basisPoints: 0  // Invalid: zero allocation
        });
        
        vm.expectRevert("Zero allocation");
        hook.validateOutputAllocations(allocations);
    }

    function test_validateOutputAllocations_revertsBelow100Percent() public {
        OutputAllocation[] memory allocations = new OutputAllocation[](2);
        allocations[0] = OutputAllocation({
            recipient: SWAPPER,
            basisPoints: 4000  // 40%
        });
        allocations[1] = OutputAllocation({
            recipient: OTHER,
            basisPoints: 5999  // 59.99% - total 99.99%
        });
        
        vm.expectRevert("Allocations not 100%");
        hook.validateOutputAllocations(allocations);
    }

    function test_validateOutputAllocations_revertsAbove100Percent() public {
        OutputAllocation[] memory allocations = new OutputAllocation[](2);
        allocations[0] = OutputAllocation({
            recipient: SWAPPER,
            basisPoints: 5000  // 50%
        });
        allocations[1] = OutputAllocation({
            recipient: OTHER,
            basisPoints: 5001  // 50.01% - total 100.01%
        });
        
        vm.expectRevert("Allocations exceed 100%");
        hook.validateOutputAllocations(allocations);
    }

    function test_validateOutputAllocations_manyRecipients() public {
        OutputAllocation[] memory allocations = new OutputAllocation[](10);
        
        for (uint256 i = 0; i < 9; i++) {
            allocations[i] = OutputAllocation({
                recipient: address(uint160(i + 1)),
                basisPoints: 1000  // 10% each
            });
        }
        
        allocations[9] = OutputAllocation({
            recipient: address(uint160(10)),
            basisPoints: 1000  // Last 10%
        });
        
        // Should not revert
        hook.validateOutputAllocations(allocations);
    }

    function testFuzz_validateOutputAllocations_validDistributions(
        uint8 numRecipients,
        uint256 seed
    ) public {
        vm.assume(numRecipients > 0 && numRecipients <= 10);
        
        OutputAllocation[] memory allocations = new OutputAllocation[](numRecipients);
        uint256 remainingBasisPoints = 10000;
        
        for (uint256 i = 0; i < numRecipients - 1; i++) {
            // Distribute randomly but ensure we don't exceed remaining
            uint256 maxAllocation = remainingBasisPoints / (numRecipients - i);
            uint256 allocation = (uint256(keccak256(abi.encode(seed, i))) % maxAllocation) + 1;
            
            allocations[i] = OutputAllocation({
                recipient: address(uint160(i + 1)),
                basisPoints: allocation
            });
            
            remainingBasisPoints -= allocation;
        }
        
        // Last recipient gets the remainder to ensure exactly 100%
        allocations[numRecipients - 1] = OutputAllocation({
            recipient: address(uint160(numRecipients)),
            basisPoints: remainingBasisPoints
        });
        
        // Should not revert for any valid distribution
        hook.validateOutputAllocations(allocations);
    }
}