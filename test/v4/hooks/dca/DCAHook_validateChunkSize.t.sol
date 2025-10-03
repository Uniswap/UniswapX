// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {DeployPermit2} from "../../../util/DeployPermit2.sol";
import {DCAHookHarness} from "./DCAHookHarness.sol";
import {IReactor} from "../../../../src/v4/interfaces/IReactor.sol";
import {DCAIntent, DCAOrderCosignerData} from "../../../../src/v4/hooks/dca/DCAStructs.sol";
import {IDCAHook} from "../../../../src/v4/interfaces/IDCAHook.sol";

contract DCAHook_validateChunkSizeTest is Test, DeployPermit2 {
    DCAHookHarness hook;
    IPermit2 permit2;
    address constant REACTOR_ADDRESS = address(0x2345);
    IReactor constant REACTOR = IReactor(REACTOR_ADDRESS);

    address constant SWAPPER = address(0x1234);
    uint256 constant NONCE = 42;

    uint256 constant MIN_CHUNK_SIZE = 10e18;
    uint256 constant MAX_CHUNK_SIZE = 100e18;

    function setUp() public {
        permit2 = IPermit2(deployPermit2());
        hook = new DCAHookHarness(permit2, REACTOR);
    }

    // ============================================
    // EXACT_IN Tests
    // ============================================

    function test_validateChunkSize_exactIn_validChunkWithinBounds() public view {
        DCAIntent memory intent = hook.createTestIntent(SWAPPER, NONCE, true, MIN_CHUNK_SIZE, MAX_CHUNK_SIZE);
        DCAOrderCosignerData memory cosignerData = hook.createTestCosignerData(SWAPPER, NONCE, 60e18, 90e18, 1);

        // Should not revert - execAmount is within bounds and matches input
        hook.validateChunkSize(intent, cosignerData, 60e18);
    }

    function test_validateChunkSize_exactIn_validChunkAtMinimum() public view {
        DCAIntent memory intent = hook.createTestIntent(SWAPPER, NONCE, true, MIN_CHUNK_SIZE, MAX_CHUNK_SIZE);
        DCAOrderCosignerData memory cosignerData = hook.createTestCosignerData(SWAPPER, NONCE, MIN_CHUNK_SIZE, 8e18, 1);

        // Should not revert - execAmount equals minimum
        hook.validateChunkSize(intent, cosignerData, MIN_CHUNK_SIZE);
    }

    function test_validateChunkSize_exactIn_validChunkAtMaximum() public view {
        DCAIntent memory intent = hook.createTestIntent(SWAPPER, NONCE, true, MIN_CHUNK_SIZE, MAX_CHUNK_SIZE);
        DCAOrderCosignerData memory cosignerData = hook.createTestCosignerData(SWAPPER, NONCE, MAX_CHUNK_SIZE, 80e18, 1);

        // Should not revert - execAmount equals maximum
        hook.validateChunkSize(intent, cosignerData, MAX_CHUNK_SIZE);
    }

    function test_validateChunkSize_exactIn_revertWhenBelowMinimum() public {
        DCAIntent memory intent = hook.createTestIntent(SWAPPER, NONCE, true, MIN_CHUNK_SIZE, MAX_CHUNK_SIZE);
        uint256 belowMin = MIN_CHUNK_SIZE - 1;
        DCAOrderCosignerData memory cosignerData = hook.createTestCosignerData(SWAPPER, NONCE, belowMin, 8e18, 1);

        vm.expectRevert(abi.encodeWithSelector(IDCAHook.InputBelowMin.selector, belowMin, MIN_CHUNK_SIZE));
        hook.validateChunkSize(intent, cosignerData, belowMin);
    }

    function test_validateChunkSize_exactIn_revertWhenAboveMaximum() public {
        DCAIntent memory intent = hook.createTestIntent(SWAPPER, NONCE, true, MIN_CHUNK_SIZE, MAX_CHUNK_SIZE);
        uint256 aboveMax = MAX_CHUNK_SIZE + 1;
        DCAOrderCosignerData memory cosignerData = hook.createTestCosignerData(SWAPPER, NONCE, aboveMax, 80e18, 1);

        vm.expectRevert(abi.encodeWithSelector(IDCAHook.InputAboveMax.selector, aboveMax, MAX_CHUNK_SIZE));
        hook.validateChunkSize(intent, cosignerData, aboveMax);
    }

    function test_validateChunkSize_exactIn_revertWhenInputMismatch() public {
        DCAIntent memory intent = hook.createTestIntent(SWAPPER, NONCE, true, MIN_CHUNK_SIZE, MAX_CHUNK_SIZE);
        DCAOrderCosignerData memory cosignerData = hook.createTestCosignerData(SWAPPER, NONCE, 50e18, 40e18, 1);
        uint256 wrongInput = 60e18;

        vm.expectRevert(abi.encodeWithSelector(IDCAHook.InputAmountMismatch.selector, wrongInput, 50e18));
        hook.validateChunkSize(intent, cosignerData, wrongInput);
    }

    function test_validateChunkSize_exactIn_revertWhenExecAmountZero() public {
        DCAIntent memory intent = hook.createTestIntent(SWAPPER, NONCE, true, 1, MAX_CHUNK_SIZE);
        DCAOrderCosignerData memory cosignerData = hook.createTestCosignerData(SWAPPER, NONCE, 0, 0, 1);

        vm.expectRevert(abi.encodeWithSelector(IDCAHook.InputBelowMin.selector, 0, 1));
        hook.validateChunkSize(intent, cosignerData, 0);
    }

    // ============================================
    // EXACT_OUT Tests
    // ============================================

    function test_validateChunkSize_exactOut_validChunkWithinBounds() public view {
        DCAIntent memory intent = hook.createTestIntent(SWAPPER, NONCE, false, MIN_CHUNK_SIZE, MAX_CHUNK_SIZE);
        DCAOrderCosignerData memory cosignerData = hook.createTestCosignerData(SWAPPER, NONCE, 50e18, 60e18, 1);

        // Should not revert - execAmount within bounds, input <= limit
        hook.validateChunkSize(intent, cosignerData, 55e18);
    }

    function test_validateChunkSize_exactOut_validChunkAtMinimum() public view {
        DCAIntent memory intent = hook.createTestIntent(SWAPPER, NONCE, false, MIN_CHUNK_SIZE, MAX_CHUNK_SIZE);
        DCAOrderCosignerData memory cosignerData = hook.createTestCosignerData(SWAPPER, NONCE, MIN_CHUNK_SIZE, 12e18, 1);

        // Should not revert - execAmount is MIN_CHUNK_SIZE so it's acceptable
        hook.validateChunkSize(intent, cosignerData, 6e18); // 6e18 input is not greater than the limit of 12e18
    }

    function test_validateChunkSize_exactOut_validChunkAtMaximum() public view {
        DCAIntent memory intent = hook.createTestIntent(SWAPPER, NONCE, false, MIN_CHUNK_SIZE, MAX_CHUNK_SIZE);
        DCAOrderCosignerData memory cosignerData =
            hook.createTestCosignerData(SWAPPER, NONCE, MAX_CHUNK_SIZE, 120e18, 1);

        // Should not revert - execAmount is MAX_CHUNK_SIZE so it's acceptables
        hook.validateChunkSize(intent, cosignerData, 110e18); // Uses 110e18 input which is not greater than the limit of 120e18
    }

    function test_validateChunkSize_exactOut_validInputAtLimit() public view {
        DCAIntent memory intent = hook.createTestIntent(SWAPPER, NONCE, false, MIN_CHUNK_SIZE, MAX_CHUNK_SIZE);
        uint256 limit = 60e18;
        DCAOrderCosignerData memory cosignerData = hook.createTestCosignerData(SWAPPER, NONCE, 50e18, limit, 1);

        // Should not revert - input exactly at limit
        hook.validateChunkSize(intent, cosignerData, limit); // Uses 60e18 input which is exactly the limit of 60e18
    }

    function test_validateChunkSize_exactOut_revertWhenBelowMinimum() public {
        DCAIntent memory intent = hook.createTestIntent(SWAPPER, NONCE, false, MIN_CHUNK_SIZE, MAX_CHUNK_SIZE);
        uint256 belowMin = MIN_CHUNK_SIZE - 1;
        DCAOrderCosignerData memory cosignerData = hook.createTestCosignerData(SWAPPER, NONCE, belowMin, 12e18, 1);

        vm.expectRevert(abi.encodeWithSelector(IDCAHook.OutputBelowMin.selector, belowMin, MIN_CHUNK_SIZE));
        // Even though the input didn't exceed the limit, the desired MAX_OUTPUT is not valid
        hook.validateChunkSize(intent, cosignerData, 10e18);
    }

    function test_validateChunkSize_exactOut_revertWhenAboveMaximum() public {
        DCAIntent memory intent = hook.createTestIntent(SWAPPER, NONCE, false, MIN_CHUNK_SIZE, MAX_CHUNK_SIZE);
        uint256 aboveMax = MAX_CHUNK_SIZE + 1;
        DCAOrderCosignerData memory cosignerData = hook.createTestCosignerData(SWAPPER, NONCE, aboveMax, 120e18, 1);

        vm.expectRevert(abi.encodeWithSelector(IDCAHook.OutputAboveMax.selector, aboveMax, MAX_CHUNK_SIZE));
        hook.validateChunkSize(intent, cosignerData, 110e18);
    }

    function test_validateChunkSize_exactOut_revertWhenZeroInput() public {
        DCAIntent memory intent = hook.createTestIntent(SWAPPER, NONCE, false, MIN_CHUNK_SIZE, MAX_CHUNK_SIZE);
        DCAOrderCosignerData memory cosignerData = hook.createTestCosignerData(SWAPPER, NONCE, 50e18, 60e18, 1);

        vm.expectRevert(IDCAHook.ZeroInput.selector);
        hook.validateChunkSize(intent, cosignerData, 0);
    }

    function test_validateChunkSize_exactOut_revertWhenInputAboveLimit() public {
        DCAIntent memory intent = hook.createTestIntent(SWAPPER, NONCE, false, MIN_CHUNK_SIZE, MAX_CHUNK_SIZE);
        uint256 limit = 60e18;
        uint256 excessiveInput = limit + 1;
        DCAOrderCosignerData memory cosignerData = hook.createTestCosignerData(SWAPPER, NONCE, 50e18, limit, 1);

        // Exceeds the maximum input the swapper is willing to give up for 50e18 of output
        vm.expectRevert(abi.encodeWithSelector(IDCAHook.InputAboveLimit.selector, excessiveInput, limit));
        hook.validateChunkSize(intent, cosignerData, excessiveInput);
    }

    // ============================================
    // Edge Cases and Boundary Tests
    // ============================================

    function test_validateChunkSize_exactIn_minMaxEqual() public view {
        uint256 fixedChunkSize = 50e18;
        DCAIntent memory intent = hook.createTestIntent(SWAPPER, NONCE, true, fixedChunkSize, fixedChunkSize);
        DCAOrderCosignerData memory cosignerData = hook.createTestCosignerData(SWAPPER, NONCE, fixedChunkSize, 40e18, 1);

        // Should not revert - execAmount equals both min and max
        hook.validateChunkSize(intent, cosignerData, fixedChunkSize);
    }

    function test_validateChunkSize_exactOut_minMaxEqual() public view {
        uint256 fixedChunkSize = 50e18;
        DCAIntent memory intent = hook.createTestIntent(SWAPPER, NONCE, false, fixedChunkSize, fixedChunkSize);
        DCAOrderCosignerData memory cosignerData = hook.createTestCosignerData(SWAPPER, NONCE, fixedChunkSize, 60e18, 1);

        // Should not revert - execAmount equals both min and max
        hook.validateChunkSize(intent, cosignerData, 55e18); // 55e18 is just a safe input that doesn't exceed 60e18
    }

    function test_validateChunkSize_exactIn_largeValues() public view {
        uint256 minChunk = 1000000e18;
        uint256 maxChunk = 10000000e18;
        uint256 execAmount = 5000000e18;
        uint256 desiredOutput = 9000000e18;

        DCAIntent memory intent = hook.createTestIntent(SWAPPER, NONCE, true, minChunk, maxChunk);
        DCAOrderCosignerData memory cosignerData =
            hook.createTestCosignerData(SWAPPER, NONCE, execAmount, desiredOutput, 1);

        // Should not revert with large values
        hook.validateChunkSize(intent, cosignerData, execAmount);
    }

    function test_validateChunkSize_exactOut_largeValues() public view {
        uint256 minChunk = 1000000e18;
        uint256 maxChunk = 10000000e18;
        uint256 execAmount = 5000000e18;
        uint256 inputAmount = 6000000e18;
        uint256 limit = 7000000e18;

        DCAIntent memory intent = hook.createTestIntent(SWAPPER, NONCE, false, minChunk, maxChunk);
        DCAOrderCosignerData memory cosignerData = hook.createTestCosignerData(SWAPPER, NONCE, execAmount, limit, 1);

        // Should not revert with large values
        hook.validateChunkSize(intent, cosignerData, inputAmount);
    }

    // ============================================
    // Fuzz Tests
    // ============================================

    function testFuzz_validateChunkSize_exactIn_validRange(uint256 minChunk, uint256 maxChunk, uint256 execAmount)
        public
        view
    {
        // Bound inputs to reasonable ranges
        minChunk = bound(minChunk, 1, type(uint128).max);
        maxChunk = bound(maxChunk, minChunk, type(uint128).max);
        execAmount = bound(execAmount, minChunk, maxChunk);

        DCAIntent memory intent = hook.createTestIntent(SWAPPER, NONCE, true, minChunk, maxChunk);
        DCAOrderCosignerData memory cosignerData =
            hook.createTestCosignerData(SWAPPER, NONCE, execAmount, execAmount / 2, 1);

        // Should not revert for any valid exec amount within bounds
        hook.validateChunkSize(intent, cosignerData, execAmount);
    }

    function testFuzz_validateChunkSize_exactOut_validRange(
        uint256 minChunk,
        uint256 maxChunk,
        uint256 execAmount,
        uint256 inputAmount
    ) public view {
        minChunk = bound(minChunk, 1, type(uint128).max);
        maxChunk = bound(maxChunk, minChunk, type(uint128).max);
        execAmount = bound(execAmount, minChunk, maxChunk);

        // For EXACT_OUT, input must be non-zero and <= limit
        inputAmount = bound(inputAmount, 1, type(uint128).max);
        uint256 limit = inputAmount + bound(inputAmount, 0, type(uint128).max);

        DCAIntent memory intent = hook.createTestIntent(SWAPPER, NONCE, false, minChunk, maxChunk);
        DCAOrderCosignerData memory cosignerData = hook.createTestCosignerData(SWAPPER, NONCE, execAmount, limit, 1);

        // Should not revert for valid combinations
        hook.validateChunkSize(intent, cosignerData, inputAmount);
    }

    function testFuzz_validateChunkSize_exactIn_revertBelowMin(uint256 minChunk, uint256 maxChunk, uint256 execAmount)
        public
    {
        // Setup reasonable bounds ensuring minChunk > 0 for valid "below" range
        minChunk = bound(minChunk, 1, type(uint128).max / 2);
        maxChunk = bound(maxChunk, minChunk, type(uint128).max);
        execAmount = bound(execAmount, 0, minChunk - 1);

        DCAIntent memory intent = hook.createTestIntent(SWAPPER, NONCE, true, minChunk, maxChunk);
        DCAOrderCosignerData memory cosignerData =
            hook.createTestCosignerData(SWAPPER, NONCE, execAmount, execAmount / 2, 1);

        vm.expectRevert(abi.encodeWithSelector(IDCAHook.InputBelowMin.selector, execAmount, minChunk));
        hook.validateChunkSize(intent, cosignerData, execAmount);
    }

    function testFuzz_validateChunkSize_exactIn_revertAboveMax(uint256 minChunk, uint256 maxChunk, uint256 execAmount)
        public
    {
        // Setup reasonable bounds
        minChunk = bound(minChunk, 1, type(uint128).max / 2);
        maxChunk = bound(maxChunk, minChunk, type(uint128).max - 1); // Leave room for above max
        execAmount = bound(execAmount, maxChunk + 1, type(uint256).max);

        DCAIntent memory intent = hook.createTestIntent(SWAPPER, NONCE, true, minChunk, maxChunk);
        DCAOrderCosignerData memory cosignerData =
            hook.createTestCosignerData(SWAPPER, NONCE, execAmount, execAmount / 2, 1);

        vm.expectRevert(abi.encodeWithSelector(IDCAHook.InputAboveMax.selector, execAmount, maxChunk));
        hook.validateChunkSize(intent, cosignerData, execAmount);
    }

    function testFuzz_validateChunkSize_exactOut_revertBelowMin(uint256 minChunk, uint256 maxChunk, uint256 execAmount)
        public
    {
        // Setup reasonable bounds ensuring minChunk > 0 for valid "below" range
        minChunk = bound(minChunk, 1, type(uint128).max / 2);
        maxChunk = bound(maxChunk, minChunk, type(uint128).max);
        execAmount = bound(execAmount, 0, minChunk - 1);

        DCAIntent memory intent = hook.createTestIntent(SWAPPER, NONCE, false, minChunk, maxChunk);
        DCAOrderCosignerData memory cosignerData =
            hook.createTestCosignerData(SWAPPER, NONCE, execAmount, type(uint128).max, 1);

        vm.expectRevert(abi.encodeWithSelector(IDCAHook.OutputBelowMin.selector, execAmount, minChunk));
        hook.validateChunkSize(intent, cosignerData, 100e18);
    }

    function testFuzz_validateChunkSize_exactOut_revertAboveMax(uint256 minChunk, uint256 maxChunk, uint256 execAmount)
        public
    {
        // Setup reasonable bounds
        minChunk = bound(minChunk, 1, type(uint128).max / 2);
        maxChunk = bound(maxChunk, minChunk, type(uint128).max - 1); // Leave room for above max
        execAmount = bound(execAmount, maxChunk + 1, type(uint256).max);

        DCAIntent memory intent = hook.createTestIntent(SWAPPER, NONCE, false, minChunk, maxChunk);
        DCAOrderCosignerData memory cosignerData =
            hook.createTestCosignerData(SWAPPER, NONCE, execAmount, type(uint128).max, 1);

        vm.expectRevert(abi.encodeWithSelector(IDCAHook.OutputAboveMax.selector, execAmount, maxChunk));
        hook.validateChunkSize(intent, cosignerData, 100e18);
    }

    function testFuzz_validateChunkSize_exactIn_inputMismatch(uint256 execAmount, uint256 inputAmount) public {
        vm.assume(execAmount != inputAmount);
        vm.assume(execAmount > 0 && execAmount <= type(uint128).max);
        vm.assume(inputAmount > 0 && inputAmount <= type(uint128).max);

        DCAIntent memory intent = hook.createTestIntent(SWAPPER, NONCE, true, 1, type(uint256).max);
        DCAOrderCosignerData memory cosignerData =
            hook.createTestCosignerData(SWAPPER, NONCE, execAmount, execAmount / 2, 1);

        vm.expectRevert(abi.encodeWithSelector(IDCAHook.InputAmountMismatch.selector, inputAmount, execAmount));
        hook.validateChunkSize(intent, cosignerData, inputAmount);
    }

    function testFuzz_validateChunkSize_exactOut_inputAboveLimit(uint256 limit, uint256 inputAmount) public {
        limit = bound(limit, 1, type(uint128).max);
        inputAmount = bound(inputAmount, limit + 1, type(uint256).max);

        DCAIntent memory intent = hook.createTestIntent(SWAPPER, NONCE, false, 1, type(uint128).max);
        DCAOrderCosignerData memory cosignerData = hook.createTestCosignerData(SWAPPER, NONCE, 50e18, limit, 1);

        vm.expectRevert(abi.encodeWithSelector(IDCAHook.InputAboveLimit.selector, inputAmount, limit));
        hook.validateChunkSize(intent, cosignerData, inputAmount);
    }
}
