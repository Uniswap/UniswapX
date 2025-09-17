// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {DeployPermit2} from "../../../util/DeployPermit2.sol";
import {DCAHookHarness} from "./DCAHookHarness.sol";
import {DCAExecutionState} from "../../../../src/v4/hooks/dca/DCAStructs.sol";

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
    
    function test_computeIntentId() public {
        bytes32 expectedId = keccak256(abi.encodePacked(SWAPPER, NONCE));
        bytes32 actualId = hook.computeIntentId(SWAPPER, NONCE);
        assertEq(actualId, expectedId, "Intent ID should match expected hash");
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
    
    function testFuzz_computeIntentId(address swapper, uint256 nonce) public {
        bytes32 expectedId = keccak256(abi.encodePacked(swapper, nonce));
        bytes32 actualId = hook.computeIntentId(swapper, nonce);
        assertEq(actualId, expectedId, "Intent ID should be deterministic");
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
    
    function test_calculatePrice() public {
        // Test normal calculation
        assertEq(hook.calculatePrice(1 ether, 2 ether), 2e18, "Price of 2 ETH out for 1 ETH in should be 2e18");
        assertEq(hook.calculatePrice(1000, 500), 5e17, "Price of 500 out for 1000 in should be 0.5e18");
        
        // Test with different decimal scales
        assertEq(hook.calculatePrice(1e6, 1e18), 1e30, "Should handle different decimal scales");
        
        // Test zero input reverts
        vm.expectRevert("input=0");
        hook.calculatePrice(0, 1000);
    }
}