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
    
    function testFuzz_computeIntentId_determinism(address swapper, uint256 nonce) public {
        // Fuzz test: verify abi.encodePacked equality for any inputs
        bytes32 expectedId = keccak256(abi.encodePacked(swapper, nonce));
        bytes32 actualId = hook.computeIntentId(swapper, nonce);
        assertEq(actualId, expectedId, "Intent ID should match abi.encodePacked for any inputs");
        
        // Verify determinism - calling again should produce same result
        bytes32 actualId2 = hook.computeIntentId(swapper, nonce);
        assertEq(actualId, actualId2, "Should be deterministic for fuzzed inputs");
    }
    
    function test_isIntentActive_uninitializedIntent() public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);
        
        // Uninitialized intent with no deadline or maxPeriod should be active
        assertTrue(hook.isIntentActive(intentId, 0, 0), "Uninitialized intent with no constraints should be active");
        
        // With deadline in future should still be active
        assertTrue(hook.isIntentActive(intentId, 0, block.timestamp + 1000), "Should be active before deadline");
        
        // With deadline in past should be inactive
        assertFalse(hook.isIntentActive(intentId, 0, block.timestamp - 21), "Should be inactive after deadline");
        
        // MaxPeriod doesn't affect uninitialized intents (no lastExecutionTime to compare)
        assertTrue(hook.isIntentActive(intentId, 3600, 0), "Uninitialized intent ignores maxPeriod");
    }
    
    function test_isIntentActive_withExecutedChunks() public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);
        // Simulate an executed chunk using harness setters
        uint256 lastExecTime = block.timestamp - 3600; // 1 hour ago
        hook.__setExecutedMeta(intentId, 1, lastExecTime);
        
        // Should be active if maxPeriod is longer than time since last execution
        assertTrue(hook.isIntentActive(intentId, 7200, 0), "Should be active within maxPeriod");
        
        // Should be inactive if maxPeriod is shorter than time since last execution
        assertFalse(hook.isIntentActive(intentId, 1800, 0), "Should be inactive after maxPeriod");
        
        // Should be inactive if deadline passed regardless of maxPeriod
        assertFalse(hook.isIntentActive(intentId, 7200, block.timestamp - 21), "Should be inactive after deadline");
    }
    
    function test_isIntentActive_cancelled() public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);
        // Set cancelled flag via harness
        hook.__setPacked(intentId, 0, true);
        
        // Should always be inactive if cancelled
        assertFalse(hook.isIntentActive(intentId, 0, 0), "Cancelled intent should be inactive");
        assertFalse(hook.isIntentActive(intentId, 0, block.timestamp + 1000), "Cancelled intent should be inactive even before deadline");
        assertFalse(hook.isIntentActive(intentId, 3600, 0), "Cancelled intent should be inactive regardless of maxPeriod");
    }
    
    function test_getNextNonce() public {
        bytes32 intentId = hook.computeIntentId(SWAPPER, NONCE);
        
        // Initially should be 0
        assertEq(hook.getNextNonce(intentId), 0, "Initial nextNonce should be 0");
        
        // Set nextNonce to 5 via harness
        hook.__setPacked(intentId, 5, false);
        
        assertEq(hook.getNextNonce(intentId), 5, "Should return stored nextNonce");
    }
    
    function test_getIntentStatistics_uninitialized() public {
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

    function test_calculatePrice_boundaryEquality() public {
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

    function test_calculatePrice_extremeValues() public {
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

    function test_calculatePrice_zeroOutputAllowed() public {
        // Zero output should be allowed (though economically meaningless)
        assertEq(hook.calculatePrice(1e18, 0), 0, "Zero output should give zero price");
        assertEq(hook.calculatePrice(1, 0), 0, "Zero output with small input");
        assertEq(hook.calculatePrice(type(uint256).max / 1e18, 0), 0, "Zero output with large input");
    }

    function test_calculatePrice_noOverflowAtBoundary() public {
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