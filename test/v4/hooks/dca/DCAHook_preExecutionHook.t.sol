// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {DeployPermit2} from "../../../util/DeployPermit2.sol";
import {DCAHook} from "../../../../src/v4/hooks/dca/DCAHook.sol";
import {DCALib} from "../../../../src/v4/hooks/dca/DCALib.sol";
import {
    DCAIntent,
    DCAOrderCosignerData,
    OutputAllocation,
    PrivateIntent,
    FeedInfo,
    PermitData,
    DCAExecutionState
} from "../../../../src/v4/hooks/dca/DCAStructs.sol";
import {ResolvedOrder, OrderInfo} from "../../../../src/v4/base/ReactorStructs.sol";
import {InputToken, OutputToken} from "../../../../src/base/ReactorStructs.sol";
import {IPreExecutionHook, IPostExecutionHook} from "../../../../src/v4/interfaces/IHook.sol";
import {IAuctionResolver} from "../../../../src/v4/interfaces/IAuctionResolver.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IReactor} from "../../../../src/v4/interfaces/IReactor.sol";
import {IDCAHook} from "../../../../src/v4/interfaces/IDCAHook.sol";
import {MockERC20} from "../../../util/mock/MockERC20.sol";

contract DCAHook_preExecutionHookTest is Test, DeployPermit2 {
    DCAHook hook;
    IPermit2 permit2;
    MockERC20 inputToken;
    MockERC20 outputToken;

    address reactor;
    address swapper;
    uint256 swapperPrivateKey;
    address cosigner;
    uint256 cosignerPrivateKey;
    address filler;

    uint256 constant INITIAL_BALANCE = 10000e18;

    // Events from IDCAHook
    event ChunkExecuted(
        bytes32 indexed intentId,
        uint256 execAmount,
        uint256 limitAmount,
        uint256 totalInputExecuted,
        uint256 totalOutput
    );

    function setUp() public {
        // Deploy Permit2
        permit2 = IPermit2(deployPermit2());

        // Setup accounts
        reactor = address(this); // Test contract acts as reactor
        swapperPrivateKey = 0xAAAAA;
        swapper = vm.addr(swapperPrivateKey);
        cosignerPrivateKey = 0xCCCCC;
        cosigner = vm.addr(cosignerPrivateKey);
        filler = address(0xFFFFFFF);

        // Deploy DCA hook
        hook = new DCAHook(permit2, IReactor(reactor));

        // Deploy mock tokens
        inputToken = new MockERC20("Input Token", "IN", 18);
        outputToken = new MockERC20("Output Token", "OUT", 18);

        // Fund swapper with input tokens
        inputToken.mint(swapper, INITIAL_BALANCE); // Gives 10,000

        // Approve Permit2 to spend swapper's tokens
        vm.prank(swapper);
        inputToken.approve(address(permit2), type(uint256).max);

        vm.warp(1000000); // Set to reasonable timestamp
    }

    /// @notice Happy path test - first chunk execution for EXACT_IN order
    function test_preExecutionHook_exactIn_firstChunk() public {
        uint256 nonce = 42; // DCA Intent nonce, NOT order nonce
        uint256 execAmount = 100e18; // Trading 100 tokens out of the 10,000
        uint256 minOutput = 180e18; // Minimum output of 180 tokens
        uint96 orderNonce = 0; // First chunk (this increments with each execution)
        bytes32 intentId = keccak256(abi.encodePacked(swapper, nonce));

        // Swapper creates the DCA intent (with full private data)
        DCAIntent memory intent = _createExactInIntent(swapper, nonce);

        // Swapper approves Permit2 allowance for the FULL DCA amount upfront
        // This approval covers all future chunks
        uint256 totalDCAAmount = 1000e18; // Total amount for all 10 chunks
        vm.prank(swapper);
        IAllowanceTransfer(address(permit2)).approve(
            address(inputToken), address(hook), uint160(totalDCAAmount), uint48(block.timestamp + 30 days)
        );

        // Compute hash of private intent data (this is what gets stored on-chain)
        bytes32 privateIntentHash = DCALib.hashPrivateIntent(intent.privateIntent);

        // Swapper signs the intent ONCE (signature is over the full intent including private data)
        // This signature will be reused for all chunks
        bytes memory swapperSignature = _signIntent(intent);

        // Zero out private intent to maintain privacy when this gets on-chain
        intent.privateIntent = PrivateIntent({
            totalAmount: 0,
            exactFrequency: 0,
            numChunks: 0,
            salt: bytes32(0),
            oracleFeeds: new FeedInfo[](0)
        });

        // Cosigner authorizes this specific execution
        DCAOrderCosignerData memory cosignerData = _createCosignerData(nonce, execAmount, minOutput, orderNonce);
        bytes memory cosignerSignature = _signCosignerData(cosignerData);

        // Build the resolved order and encode hook data
        ResolvedOrder memory resolvedOrder = _createResolvedOrder(intent, execAmount, minOutput);
        resolvedOrder.info.preExecutionHookData =
            _encodeHookData(intent, swapperSignature, privateIntentHash, cosignerData, cosignerSignature);

        // Execute the hook (filler calls this)
        vm.expectEmit(true, false, false, true);
        emit ChunkExecuted(intentId, execAmount, minOutput, execAmount, minOutput);
        hook.preExecutionHook(filler, resolvedOrder);

        // Verify execution state was updated correctly
        DCAExecutionState memory state = hook.getExecutionState(intentId);
        assertEq(state.executedChunks, 1);
        assertEq(state.lastExecutionTime, block.timestamp);
        assertEq(state.totalInputExecuted, execAmount);
        assertEq(state.totalOutput, minOutput);
        assertFalse(state.cancelled);
    }

    /// @notice Happy path test - second chunk execution for EXACT_IN order
    function test_preExecutionHook_exactIn_secondChunk() public {
        // Execute first chunk
        test_preExecutionHook_exactIn_firstChunk();

        // Fast forward time to meet minPeriod requirement
        vm.warp(block.timestamp + 400);

        uint256 nonce = 42; // Same DCA intent
        uint256 execAmount = 100e18;
        uint256 minOutput = 185e18; // Better price for second chunk
        uint96 orderNonce = 1; // Second chunk
        bytes32 intentId = keccak256(abi.encodePacked(swapper, nonce));

        // Swapper already approved and signed in the first chunk - NO need to do it again!
        // We just need to reconstruct the intent and get the same signature

        // Reconstruct the DCA intent (with full private data)
        DCAIntent memory intent = _createExactInIntent(swapper, nonce);

        // Compute the same hash of private intent data
        bytes32 privateIntentHash = DCALib.hashPrivateIntent(intent.privateIntent);

        // Get the swapper signature (same as first chunk - intent hasn't changed)
        bytes memory swapperSignature = _signIntent(intent);

        // Zero out private intent to maintain privacy on-chain
        intent.privateIntent = PrivateIntent({
            totalAmount: 0,
            exactFrequency: 0,
            numChunks: 0,
            salt: bytes32(0),
            oracleFeeds: new FeedInfo[](0)
        });

        // Cosigner authorizes this second execution (different orderNonce)
        DCAOrderCosignerData memory cosignerData = _createCosignerData(nonce, execAmount, minOutput, orderNonce);
        bytes memory cosignerSignature = _signCosignerData(cosignerData);

        // Build the resolved order and encode hook data
        ResolvedOrder memory resolvedOrder = _createResolvedOrder(intent, execAmount, minOutput);
        resolvedOrder.info.preExecutionHookData =
            _encodeHookData(intent, swapperSignature, privateIntentHash, cosignerData, cosignerSignature);

        // Get expected cumulative values
        DCAExecutionState memory stateBefore = hook.getExecutionState(intentId);
        uint256 expectedTotalInput = stateBefore.totalInputExecuted + execAmount;
        uint256 expectedTotalOutput = stateBefore.totalOutput + minOutput;

        // Execute the hook (filler calls this)
        vm.expectEmit(true, false, false, true);
        emit ChunkExecuted(intentId, execAmount, minOutput, expectedTotalInput, expectedTotalOutput);
        hook.preExecutionHook(filler, resolvedOrder);

        // Verify execution state was updated correctly
        DCAExecutionState memory state = hook.getExecutionState(intentId);
        assertEq(state.executedChunks, 2);
        assertEq(state.lastExecutionTime, block.timestamp);
        assertEq(state.totalInputExecuted, expectedTotalInput);
        assertEq(state.totalOutput, expectedTotalOutput);
        assertFalse(state.cancelled);
    }

    // /// @notice Happy path test - EXACT_OUT order
    /// @notice Happy path test - first chunk execution for EXACT_OUT order
    function test_preExecutionHook_exactOut_firstChunk() public {
        uint256 nonce = 43;
        bytes32 intentId = keccak256(abi.encodePacked(swapper, nonce));

        // Swapper creates the DCA intent for EXACT_OUT (wants 2000 tokens output total)
        DCAIntent memory intent = _createExactOutIntent(swapper, nonce);

        // Swapper approves Permit2 allowance for max possible input (1100e18 for all chunks)
        vm.prank(swapper);
        IAllowanceTransfer(address(permit2)).approve(
            address(inputToken), address(hook), 1100e18, uint48(block.timestamp + 30 days)
        );

        // Compute hash and sign
        bytes32 privateIntentHash = DCALib.hashPrivateIntent(intent.privateIntent);
        bytes memory swapperSignature = _signIntent(intent);

        // Zero out private intent
        intent.privateIntent = PrivateIntent({
            totalAmount: 0,
            exactFrequency: 0,
            numChunks: 0,
            salt: bytes32(0),
            oracleFeeds: new FeedInfo[](0)
        });

        // Cosigner authorizes: execAmount=200e18 (output), limitAmount=110e18 (max input)
        DCAOrderCosignerData memory cosignerData = _createCosignerData(nonce, 200e18, 110e18, 0);
        bytes memory cosignerSignature = _signCosignerData(cosignerData);

        // Build resolved order: actualInput=105e18, exactOutput=200e18
        ResolvedOrder memory resolvedOrder = _createResolvedOrder(intent, 105e18, 200e18);
        resolvedOrder.info.preExecutionHookData =
            _encodeHookData(intent, swapperSignature, privateIntentHash, cosignerData, cosignerSignature);

        // Execute
        vm.expectEmit(true, false, false, true);
        emit ChunkExecuted(intentId, 200e18, 110e18, 105e18, 200e18);
        hook.preExecutionHook(filler, resolvedOrder);

        // Verify
        DCAExecutionState memory state = hook.getExecutionState(intentId);
        assertEq(state.executedChunks, 1);
        assertEq(state.totalInputExecuted, 105e18);
        assertEq(state.totalOutput, 200e18);
    }

    /// @notice Test with multiple output recipients (90% to swapper, 10% to fee recipient)
    function test_preExecutionHook_multipleRecipients() public {
        uint256 nonce = 44;
        bytes32 intentId = keccak256(abi.encodePacked(swapper, nonce));

        // Swapper creates DCA intent with multiple output recipients (90% swapper, 10% fee)
        DCAIntent memory intent = _createExactInIntentMultipleRecipients(swapper, nonce);

        // Swapper approves full DCA amount
        vm.prank(swapper);
        IAllowanceTransfer(address(permit2)).approve(
            address(inputToken), address(hook), 1000e18, uint48(block.timestamp + 30 days)
        );

        // Compute hash and sign
        bytes32 privateIntentHash = DCALib.hashPrivateIntent(intent.privateIntent);
        bytes memory swapperSignature = _signIntent(intent);

        // Zero out private intent
        intent.privateIntent = PrivateIntent({
            totalAmount: 0,
            exactFrequency: 0,
            numChunks: 0,
            salt: bytes32(0),
            oracleFeeds: new FeedInfo[](0)
        });

        // Cosigner authorizes execution
        DCAOrderCosignerData memory cosignerData = _createCosignerData(nonce, 100e18, 180e18, 0);
        bytes memory cosignerSignature = _signCosignerData(cosignerData);

        // Build resolved order with multiple recipients (90% to swapper, 10% to fee)
        address feeRecipient = address(0xFEE);
        ResolvedOrder memory resolvedOrder =
            _createResolvedOrderMultipleRecipients(intent, 100e18, 180e18, feeRecipient);
        resolvedOrder.info.preExecutionHookData =
            _encodeHookData(intent, swapperSignature, privateIntentHash, cosignerData, cosignerSignature);

        // Execute
        vm.expectEmit(true, false, false, true);
        emit ChunkExecuted(intentId, 100e18, 180e18, 100e18, 180e18);
        hook.preExecutionHook(filler, resolvedOrder);

        // Verify
        DCAExecutionState memory state = hook.getExecutionState(intentId);
        assertEq(state.executedChunks, 1);
        assertEq(state.totalInputExecuted, 100e18);
        assertEq(state.totalOutput, 180e18);
    }

    // ============ Unhappy Path Tests ============

    /// @notice Test that executing a cancelled intent reverts with IntentIsCancelled
    function test_preExecutionHook_revert_intentIsCancelled() public {
        uint256 nonce = 50;
        bytes32 intentId = keccak256(abi.encodePacked(swapper, nonce));

        // Swapper creates and approves the DCA intent
        DCAIntent memory intent = _createExactInIntent(swapper, nonce);
        vm.prank(swapper);
        IAllowanceTransfer(address(permit2)).approve(
            address(inputToken), address(hook), 1000e18, uint48(block.timestamp + 30 days)
        );

        // Swapper cancels the intent
        vm.prank(swapper);
        hook.cancelIntent(nonce);

        // Verify it's cancelled
        DCAExecutionState memory state = hook.getExecutionState(intentId);
        assertTrue(state.cancelled);

        // Now try to execute the cancelled intent
        bytes32 privateIntentHash = DCALib.hashPrivateIntent(intent.privateIntent);
        bytes memory swapperSignature = _signIntent(intent);

        intent.privateIntent = PrivateIntent({
            totalAmount: 0,
            exactFrequency: 0,
            numChunks: 0,
            salt: bytes32(0),
            oracleFeeds: new FeedInfo[](0)
        });

        DCAOrderCosignerData memory cosignerData = _createCosignerData(nonce, 100e18, 180e18, 0);
        bytes memory cosignerSignature = _signCosignerData(cosignerData);

        ResolvedOrder memory resolvedOrder = _createResolvedOrder(intent, 100e18, 180e18);
        resolvedOrder.info.preExecutionHookData =
            _encodeHookData(intent, swapperSignature, privateIntentHash, cosignerData, cosignerSignature);

        // Should revert with IntentIsCancelled
        vm.expectRevert(abi.encodeWithSelector(IDCAHook.IntentIsCancelled.selector, intentId));
        hook.preExecutionHook(filler, resolvedOrder);
    }

    /// @notice Test that an invalid swapper signature reverts
    function test_revert_invalidSwapperSignature() public {
        uint256 nonce = 52;

        // Swapper creates intent and approves
        DCAIntent memory intent = _createExactInIntent(swapper, nonce);
        vm.prank(swapper);
        IAllowanceTransfer(address(permit2)).approve(
            address(inputToken), address(hook), 1000e18, uint48(block.timestamp + 30 days)
        );

        // Compute hash
        bytes32 privateIntentHash = DCALib.hashPrivateIntent(intent.privateIntent);

        // WRONG: Sign with a different private key (not the swapper's key)
        uint256 wrongPrivateKey = 0x9999;
        address wrongSigner = vm.addr(wrongPrivateKey);
        bytes32 intentHash = DCALib.hash(intent);
        bytes32 digest = DCALib.digest(hook.domainSeparator(), intentHash);
        bytes memory invalidSignature = _sign(wrongPrivateKey, digest);

        // Zero out private intent
        intent.privateIntent = PrivateIntent({
            totalAmount: 0,
            exactFrequency: 0,
            numChunks: 0,
            salt: bytes32(0),
            oracleFeeds: new FeedInfo[](0)
        });

        // Cosigner authorizes
        DCAOrderCosignerData memory cosignerData = _createCosignerData(nonce, 100e18, 180e18, 0);
        bytes memory cosignerSignature = _signCosignerData(cosignerData);

        // Build resolved order with invalid signature
        ResolvedOrder memory resolvedOrder = _createResolvedOrder(intent, 100e18, 180e18);
        resolvedOrder.info.preExecutionHookData =
            _encodeHookData(intent, invalidSignature, privateIntentHash, cosignerData, cosignerSignature);

        // Should revert with InvalidSwapperSignature
        vm.expectRevert(abi.encodeWithSelector(IDCAHook.InvalidSwapperSignature.selector, wrongSigner, swapper));
        hook.preExecutionHook(filler, resolvedOrder);
    }

    /// @notice Test WrongHook error when intent specifies different hook address
    function test_revert_wrongHook() public {
        uint256 nonce = 60;
        address wrongHook = address(0xBAD);

        DCAIntent memory intent = _createExactInIntent(swapper, nonce);
        intent.hookAddress = wrongHook; // Intentionally wrong

        _testStaticFieldValidationError(
            intent, nonce, abi.encodeWithSelector(IDCAHook.WrongHook.selector, wrongHook, address(hook))
        );
    }

    /// @notice Test WrongChain error when intent specifies different chain ID
    function test_revert_wrongChain() public {
        uint256 nonce = 61;
        uint256 wrongChainId = 999;

        DCAIntent memory intent = _createExactInIntent(swapper, nonce);
        intent.chainId = wrongChainId; // Intentionally wrong

        _testStaticFieldValidationError(
            intent, nonce, abi.encodeWithSelector(IDCAHook.WrongChain.selector, wrongChainId, block.chainid)
        );
    }

    /// @notice Test SwapperMismatch error when resolved order has different swapper
    function test_revert_swapperMismatch() public {
        uint256 nonce = 62;
        address differentSwapper = address(0xDEAD);

        DCAIntent memory intent = _createExactInIntent(swapper, nonce);

        // Create resolved order with DIFFERENT swapper
        ResolvedOrder memory resolvedOrder = _createResolvedOrder(intent, 100e18, 180e18);
        resolvedOrder.info.swapper = differentSwapper; // Intentionally wrong

        // Setup signatures and hook data
        vm.prank(swapper);
        IAllowanceTransfer(address(permit2)).approve(
            address(inputToken), address(hook), 1000e18, uint48(block.timestamp + 30 days)
        );

        bytes32 privateIntentHash = DCALib.hashPrivateIntent(intent.privateIntent);
        bytes memory swapperSignature = _signIntent(intent);

        intent.privateIntent = PrivateIntent({
            totalAmount: 0,
            exactFrequency: 0,
            numChunks: 0,
            salt: bytes32(0),
            oracleFeeds: new FeedInfo[](0)
        });

        DCAOrderCosignerData memory cosignerData = _createCosignerData(nonce, 100e18, 180e18, 0);
        bytes memory cosignerSignature = _signCosignerData(cosignerData);

        resolvedOrder.info.preExecutionHookData =
            _encodeHookData(intent, swapperSignature, privateIntentHash, cosignerData, cosignerSignature);

        // Should revert with SwapperMismatch
        vm.expectRevert(abi.encodeWithSelector(IDCAHook.SwapperMismatch.selector, differentSwapper, swapper));
        hook.preExecutionHook(filler, resolvedOrder);
    }

    /// @notice Test WrongInputToken error
    function test_revert_wrongInputToken() public {
        uint256 nonce = 63;
        MockERC20 wrongToken = new MockERC20("Wrong", "WRONG", 18);

        DCAIntent memory intent = _createExactInIntent(swapper, nonce);

        // Create resolved order with WRONG input token
        ResolvedOrder memory resolvedOrder = _createResolvedOrder(intent, 100e18, 180e18);
        resolvedOrder.input.token = ERC20(address(wrongToken)); // Intentionally wrong

        _setupAndTestValidationError(
            intent,
            nonce,
            resolvedOrder,
            abi.encodeWithSelector(IDCAHook.WrongInputToken.selector, address(wrongToken), address(inputToken))
        );
    }

    /// @notice Test WrongOutputToken error
    function test_revert_wrongOutputToken() public {
        uint256 nonce = 64;
        MockERC20 wrongToken = new MockERC20("Wrong", "WRONG", 18);

        DCAIntent memory intent = _createExactInIntent(swapper, nonce);

        // Create resolved order with WRONG output token
        ResolvedOrder memory resolvedOrder = _createResolvedOrder(intent, 100e18, 180e18);
        resolvedOrder.outputs[0].token = address(wrongToken); // Intentionally wrong

        _setupAndTestValidationError(
            intent,
            nonce,
            resolvedOrder,
            abi.encodeWithSelector(IDCAHook.WrongOutputToken.selector, address(wrongToken), address(outputToken))
        );
    }

    /// @notice Test EmptyAllocations error when outputAllocations array is empty
    function test_revert_emptyAllocations() public {
        uint256 nonce = 65;

        DCAIntent memory intent = _createExactInIntent(swapper, nonce);
        intent.outputAllocations = new OutputAllocation[](0); // Intentionally empty

        _testStaticFieldValidationError(intent, nonce, abi.encodeWithSelector(IDCAHook.EmptyAllocations.selector));
    }

    /// @notice Test ZeroAllocation error when an allocation has 0 basis points
    function test_revert_zeroAllocation() public {
        uint256 nonce = 66;

        DCAIntent memory intent = _createExactInIntent(swapper, nonce);
        OutputAllocation[] memory allocations = new OutputAllocation[](1);
        allocations[0] = OutputAllocation({recipient: swapper, basisPoints: 0}); // Intentionally zero
        intent.outputAllocations = allocations;

        _testStaticFieldValidationError(intent, nonce, abi.encodeWithSelector(IDCAHook.ZeroAllocation.selector));
    }

    /// @notice Test AllocationsNot100Percent error when allocations don't sum to 10000 bps
    function test_revert_allocationsNot100Percent() public {
        uint256 nonce = 67;

        DCAIntent memory intent = _createExactInIntent(swapper, nonce);
        OutputAllocation[] memory allocations = new OutputAllocation[](2);
        allocations[0] = OutputAllocation({recipient: swapper, basisPoints: 5000}); // 50%
        allocations[1] = OutputAllocation({recipient: address(0xFEE), basisPoints: 3000}); // 30%
        // Total = 8000, not 10000
        intent.outputAllocations = allocations;

        _testStaticFieldValidationError(
            intent, nonce, abi.encodeWithSelector(IDCAHook.AllocationsNot100Percent.selector, 8000)
        );
    }

    /// @notice Test InvalidCosignerSignature error when cosigner signature is invalid
    function test_revert_invalidCosignerSignature() public {
        uint256 nonce = 68;

        DCAIntent memory intent = _createExactInIntent(swapper, nonce);
        vm.prank(swapper);
        IAllowanceTransfer(address(permit2)).approve(
            address(inputToken), address(hook), 1000e18, uint48(block.timestamp + 30 days)
        );

        bytes32 privateIntentHash = DCALib.hashPrivateIntent(intent.privateIntent);
        bytes memory swapperSignature = _signIntent(intent);

        intent.privateIntent = PrivateIntent({
            totalAmount: 0,
            exactFrequency: 0,
            numChunks: 0,
            salt: bytes32(0),
            oracleFeeds: new FeedInfo[](0)
        });

        DCAOrderCosignerData memory cosignerData = _createCosignerData(nonce, 100e18, 180e18, 0);

        // WRONG: Sign with wrong private key
        uint256 wrongPrivateKey = 0x8888;
        address wrongCosigner = vm.addr(wrongPrivateKey);
        bytes32 cosignerStructHash = DCALib.hashCosignerData(cosignerData);
        bytes32 cosignerDigest = DCALib.digest(hook.domainSeparator(), cosignerStructHash);
        bytes memory invalidCosignerSignature = _sign(wrongPrivateKey, cosignerDigest);

        ResolvedOrder memory resolvedOrder = _createResolvedOrder(intent, 100e18, 180e18);
        resolvedOrder.info.preExecutionHookData =
            _encodeHookData(intent, swapperSignature, privateIntentHash, cosignerData, invalidCosignerSignature);

        vm.expectRevert(abi.encodeWithSelector(IDCAHook.InvalidCosignerSignature.selector, wrongCosigner, cosigner));
        hook.preExecutionHook(filler, resolvedOrder);
    }

    /// @notice Test CosignerSwapperMismatch error when cosignerData has wrong swapper
    function test_revert_cosignerSwapperMismatch() public {
        uint256 nonce = 69;
        address wrongSwapper = address(0xBADBAD);

        DCAIntent memory intent = _createExactInIntent(swapper, nonce);
        vm.prank(swapper);
        IAllowanceTransfer(address(permit2)).approve(
            address(inputToken), address(hook), 1000e18, uint48(block.timestamp + 30 days)
        );

        bytes32 privateIntentHash = DCALib.hashPrivateIntent(intent.privateIntent);
        bytes memory swapperSignature = _signIntent(intent);

        intent.privateIntent = PrivateIntent({
            totalAmount: 0,
            exactFrequency: 0,
            numChunks: 0,
            salt: bytes32(0),
            oracleFeeds: new FeedInfo[](0)
        });

        // Create cosigner data with WRONG swapper
        DCAOrderCosignerData memory cosignerData = DCAOrderCosignerData({
            swapper: wrongSwapper, // Intentionally wrong
            nonce: uint96(nonce),
            execAmount: uint160(100e18),
            orderNonce: 0,
            limitAmount: uint160(180e18)
        });
        bytes memory cosignerSignature = _signCosignerData(cosignerData);

        ResolvedOrder memory resolvedOrder = _createResolvedOrder(intent, 100e18, 180e18);
        resolvedOrder.info.preExecutionHookData =
            _encodeHookData(intent, swapperSignature, privateIntentHash, cosignerData, cosignerSignature);

        vm.expectRevert(abi.encodeWithSelector(IDCAHook.CosignerSwapperMismatch.selector, wrongSwapper, swapper));
        hook.preExecutionHook(filler, resolvedOrder);
    }

    /// @notice Test CosignerNonceMismatch error when cosignerData has wrong nonce
    function test_revert_cosignerNonceMismatch() public {
        uint256 nonce = 70;
        uint96 wrongNonce = 999;

        DCAIntent memory intent = _createExactInIntent(swapper, nonce);
        vm.prank(swapper);
        IAllowanceTransfer(address(permit2)).approve(
            address(inputToken), address(hook), 1000e18, uint48(block.timestamp + 30 days)
        );

        bytes32 privateIntentHash = DCALib.hashPrivateIntent(intent.privateIntent);
        bytes memory swapperSignature = _signIntent(intent);

        intent.privateIntent = PrivateIntent({
            totalAmount: 0,
            exactFrequency: 0,
            numChunks: 0,
            salt: bytes32(0),
            oracleFeeds: new FeedInfo[](0)
        });

        // Create cosigner data with WRONG nonce
        DCAOrderCosignerData memory cosignerData = DCAOrderCosignerData({
            swapper: swapper,
            nonce: wrongNonce, // Intentionally wrong
            execAmount: uint160(100e18),
            orderNonce: 0,
            limitAmount: uint160(180e18)
        });
        bytes memory cosignerSignature = _signCosignerData(cosignerData);

        ResolvedOrder memory resolvedOrder = _createResolvedOrder(intent, 100e18, 180e18);
        resolvedOrder.info.preExecutionHookData =
            _encodeHookData(intent, swapperSignature, privateIntentHash, cosignerData, cosignerSignature);

        vm.expectRevert(abi.encodeWithSelector(IDCAHook.CosignerNonceMismatch.selector, wrongNonce, nonce));
        hook.preExecutionHook(filler, resolvedOrder);
    }

    /// @notice Test IntentExpired error when current time exceeds deadline
    function test_revert_intentExpired() public {
        uint256 nonce = 71;

        DCAIntent memory intent = _createExactInIntent(swapper, nonce);
        intent.deadline = block.timestamp + 1 days;

        vm.prank(swapper);
        IAllowanceTransfer(address(permit2)).approve(
            address(inputToken), address(hook), 1000e18, uint48(block.timestamp + 30 days)
        );

        bytes32 privateIntentHash = DCALib.hashPrivateIntent(intent.privateIntent);
        bytes memory swapperSignature = _signIntent(intent);

        intent.privateIntent = PrivateIntent({
            totalAmount: 0,
            exactFrequency: 0,
            numChunks: 0,
            salt: bytes32(0),
            oracleFeeds: new FeedInfo[](0)
        });

        DCAOrderCosignerData memory cosignerData = _createCosignerData(nonce, 100e18, 180e18, 0);
        bytes memory cosignerSignature = _signCosignerData(cosignerData);

        ResolvedOrder memory resolvedOrder = _createResolvedOrder(intent, 100e18, 180e18);
        resolvedOrder.info.deadline = block.timestamp + 1 days;
        resolvedOrder.info.preExecutionHookData =
            _encodeHookData(intent, swapperSignature, privateIntentHash, cosignerData, cosignerSignature);

        // Fast forward past deadline
        vm.warp(block.timestamp + 1 days + 1);

        uint256 currentTime = block.timestamp;
        uint256 deadline = block.timestamp - 1;
        vm.expectRevert(abi.encodeWithSelector(IDCAHook.IntentExpired.selector, currentTime, deadline));
        hook.preExecutionHook(filler, resolvedOrder);
    }

    /// @notice Test WrongChunkNonce error when orderNonce doesn't match executedChunks
    function test_revert_wrongChunkNonce() public {
        uint256 nonce = 72;

        // Execute first chunk successfully
        DCAIntent memory intent = _createExactInIntent(swapper, nonce);
        vm.prank(swapper);
        IAllowanceTransfer(address(permit2)).approve(
            address(inputToken), address(hook), 1000e18, uint48(block.timestamp + 30 days)
        );

        bytes32 privateIntentHash = DCALib.hashPrivateIntent(intent.privateIntent);
        bytes memory swapperSignature = _signIntent(intent);

        intent.privateIntent = PrivateIntent({
            totalAmount: 0,
            exactFrequency: 0,
            numChunks: 0,
            salt: bytes32(0),
            oracleFeeds: new FeedInfo[](0)
        });

        DCAOrderCosignerData memory cosignerData = _createCosignerData(nonce, 100e18, 180e18, 0);
        bytes memory cosignerSignature = _signCosignerData(cosignerData);

        ResolvedOrder memory resolvedOrder = _createResolvedOrder(intent, 100e18, 180e18);
        resolvedOrder.info.preExecutionHookData =
            _encodeHookData(intent, swapperSignature, privateIntentHash, cosignerData, cosignerSignature);

        hook.preExecutionHook(filler, resolvedOrder);

        // Now try second chunk with WRONG orderNonce (should be 1, but use 5)
        vm.warp(block.timestamp + 400);

        DCAIntent memory intent2 = _createExactInIntent(swapper, nonce);
        bytes32 privateIntentHash2 = DCALib.hashPrivateIntent(intent2.privateIntent);
        bytes memory swapperSignature2 = _signIntent(intent2);

        intent2.privateIntent = PrivateIntent({
            totalAmount: 0,
            exactFrequency: 0,
            numChunks: 0,
            salt: bytes32(0),
            oracleFeeds: new FeedInfo[](0)
        });

        // Use orderNonce = 5 instead of 1
        uint96 wrongOrderNonce = 5;
        DCAOrderCosignerData memory cosignerData2 = _createCosignerData(nonce, 100e18, 185e18, wrongOrderNonce);
        bytes memory cosignerSignature2 = _signCosignerData(cosignerData2);

        ResolvedOrder memory resolvedOrder2 = _createResolvedOrder(intent2, 100e18, 185e18);
        resolvedOrder2.info.preExecutionHookData =
            _encodeHookData(intent2, swapperSignature2, privateIntentHash2, cosignerData2, cosignerSignature2);

        vm.expectRevert(abi.encodeWithSelector(IDCAHook.WrongChunkNonce.selector, wrongOrderNonce, uint96(1)));
        hook.preExecutionHook(filler, resolvedOrder2);
    }

    /// @notice Test TooSoon error when executing before minPeriod has elapsed
    function test_revert_tooSoon() public {
        uint256 nonce = 73;

        // Execute first chunk successfully
        DCAIntent memory intent = _createExactInIntent(swapper, nonce);
        vm.prank(swapper);
        IAllowanceTransfer(address(permit2)).approve(
            address(inputToken), address(hook), 1000e18, uint48(block.timestamp + 30 days)
        );

        bytes32 privateIntentHash = DCALib.hashPrivateIntent(intent.privateIntent);
        bytes memory swapperSignature = _signIntent(intent);

        intent.privateIntent = PrivateIntent({
            totalAmount: 0,
            exactFrequency: 0,
            numChunks: 0,
            salt: bytes32(0),
            oracleFeeds: new FeedInfo[](0)
        });

        DCAOrderCosignerData memory cosignerData = _createCosignerData(nonce, 100e18, 180e18, 0);
        bytes memory cosignerSignature = _signCosignerData(cosignerData);

        ResolvedOrder memory resolvedOrder = _createResolvedOrder(intent, 100e18, 180e18);
        resolvedOrder.info.preExecutionHookData =
            _encodeHookData(intent, swapperSignature, privateIntentHash, cosignerData, cosignerSignature);

        hook.preExecutionHook(filler, resolvedOrder);

        // Try second chunk too soon (minPeriod is 300, only wait 100)
        vm.warp(block.timestamp + 100);

        DCAIntent memory intent2 = _createExactInIntent(swapper, nonce);
        bytes32 privateIntentHash2 = DCALib.hashPrivateIntent(intent2.privateIntent);
        bytes memory swapperSignature2 = _signIntent(intent2);

        intent2.privateIntent = PrivateIntent({
            totalAmount: 0,
            exactFrequency: 0,
            numChunks: 0,
            salt: bytes32(0),
            oracleFeeds: new FeedInfo[](0)
        });

        DCAOrderCosignerData memory cosignerData2 = _createCosignerData(nonce, 100e18, 185e18, 1);
        bytes memory cosignerSignature2 = _signCosignerData(cosignerData2);

        ResolvedOrder memory resolvedOrder2 = _createResolvedOrder(intent2, 100e18, 185e18);
        resolvedOrder2.info.preExecutionHookData =
            _encodeHookData(intent2, swapperSignature2, privateIntentHash2, cosignerData2, cosignerSignature2);

        vm.expectRevert(abi.encodeWithSelector(IDCAHook.TooSoon.selector, 100, 300));
        hook.preExecutionHook(filler, resolvedOrder2);
    }

    /// @notice Test TooLate error when executing after maxPeriod has elapsed
    function test_revert_tooLate() public {
        uint256 nonce = 74;

        // Execute first chunk successfully
        DCAIntent memory intent = _createExactInIntent(swapper, nonce);
        vm.prank(swapper);
        IAllowanceTransfer(address(permit2)).approve(
            address(inputToken), address(hook), 1000e18, uint48(block.timestamp + 30 days)
        );

        bytes32 privateIntentHash = DCALib.hashPrivateIntent(intent.privateIntent);
        bytes memory swapperSignature = _signIntent(intent);

        intent.privateIntent = PrivateIntent({
            totalAmount: 0,
            exactFrequency: 0,
            numChunks: 0,
            salt: bytes32(0),
            oracleFeeds: new FeedInfo[](0)
        });

        DCAOrderCosignerData memory cosignerData = _createCosignerData(nonce, 100e18, 180e18, 0);
        bytes memory cosignerSignature = _signCosignerData(cosignerData);

        ResolvedOrder memory resolvedOrder = _createResolvedOrder(intent, 100e18, 180e18);
        resolvedOrder.info.preExecutionHookData =
            _encodeHookData(intent, swapperSignature, privateIntentHash, cosignerData, cosignerSignature);

        hook.preExecutionHook(filler, resolvedOrder);

        // Try second chunk too late (maxPeriod is 7200, wait 10000)
        vm.warp(block.timestamp + 10000);

        DCAIntent memory intent2 = _createExactInIntent(swapper, nonce);
        bytes32 privateIntentHash2 = DCALib.hashPrivateIntent(intent2.privateIntent);
        bytes memory swapperSignature2 = _signIntent(intent2);

        intent2.privateIntent = PrivateIntent({
            totalAmount: 0,
            exactFrequency: 0,
            numChunks: 0,
            salt: bytes32(0),
            oracleFeeds: new FeedInfo[](0)
        });

        DCAOrderCosignerData memory cosignerData2 = _createCosignerData(nonce, 100e18, 185e18, 1);
        bytes memory cosignerSignature2 = _signCosignerData(cosignerData2);

        ResolvedOrder memory resolvedOrder2 = _createResolvedOrder(intent2, 100e18, 185e18);
        resolvedOrder2.info.preExecutionHookData =
            _encodeHookData(intent2, swapperSignature2, privateIntentHash2, cosignerData2, cosignerSignature2);

        vm.expectRevert(abi.encodeWithSelector(IDCAHook.TooLate.selector, 10000, 7200));
        hook.preExecutionHook(filler, resolvedOrder2);
    }

    /// @notice Test ChunkSizeBelowMin error when execAmount is below minChunkSize
    function test_revert_chunkSizeBelowMin() public {
        uint256 nonce = 75;

        DCAIntent memory intent = _createExactInIntent(swapper, nonce);
        vm.prank(swapper);
        IAllowanceTransfer(address(permit2)).approve(
            address(inputToken), address(hook), 1000e18, uint48(block.timestamp + 30 days)
        );

        bytes32 privateIntentHash = DCALib.hashPrivateIntent(intent.privateIntent);
        bytes memory swapperSignature = _signIntent(intent);

        intent.privateIntent = PrivateIntent({
            totalAmount: 0,
            exactFrequency: 0,
            numChunks: 0,
            salt: bytes32(0),
            oracleFeeds: new FeedInfo[](0)
        });

        // Cosigner sets execAmount = 40e18, which is below minChunkSize of 50e18
        uint256 tooSmallAmount = 40e18;
        DCAOrderCosignerData memory cosignerData = _createCosignerData(nonce, tooSmallAmount, 80e18, 0);
        bytes memory cosignerSignature = _signCosignerData(cosignerData);

        ResolvedOrder memory resolvedOrder = _createResolvedOrder(intent, tooSmallAmount, 80e18);
        resolvedOrder.info.preExecutionHookData =
            _encodeHookData(intent, swapperSignature, privateIntentHash, cosignerData, cosignerSignature);

        vm.expectRevert(abi.encodeWithSelector(IDCAHook.ChunkSizeBelowMin.selector, tooSmallAmount, 50e18));
        hook.preExecutionHook(filler, resolvedOrder);
    }

    /// @notice Test ChunkSizeAboveMax error when execAmount exceeds maxChunkSize
    function test_revert_chunkSizeAboveMax() public {
        uint256 nonce = 76;

        DCAIntent memory intent = _createExactInIntent(swapper, nonce);
        vm.prank(swapper);
        IAllowanceTransfer(address(permit2)).approve(
            address(inputToken), address(hook), 1000e18, uint48(block.timestamp + 30 days)
        );

        bytes32 privateIntentHash = DCALib.hashPrivateIntent(intent.privateIntent);
        bytes memory swapperSignature = _signIntent(intent);

        intent.privateIntent = PrivateIntent({
            totalAmount: 0,
            exactFrequency: 0,
            numChunks: 0,
            salt: bytes32(0),
            oracleFeeds: new FeedInfo[](0)
        });

        // Cosigner sets execAmount = 250e18, which exceeds maxChunkSize of 200e18
        uint256 tooLargeAmount = 250e18;
        DCAOrderCosignerData memory cosignerData = _createCosignerData(nonce, tooLargeAmount, 500e18, 0);
        bytes memory cosignerSignature = _signCosignerData(cosignerData);

        ResolvedOrder memory resolvedOrder = _createResolvedOrder(intent, tooLargeAmount, 500e18);
        resolvedOrder.info.preExecutionHookData =
            _encodeHookData(intent, swapperSignature, privateIntentHash, cosignerData, cosignerSignature);

        vm.expectRevert(abi.encodeWithSelector(IDCAHook.ChunkSizeAboveMax.selector, tooLargeAmount, 200e18));
        hook.preExecutionHook(filler, resolvedOrder);
    }

    /// @notice Test InputAmountMismatch error for EXACT_IN when input doesn't match execAmount
    function test_revert_inputAmountMismatch() public {
        uint256 nonce = 77;

        DCAIntent memory intent = _createExactInIntent(swapper, nonce);
        vm.prank(swapper);
        IAllowanceTransfer(address(permit2)).approve(
            address(inputToken), address(hook), 1000e18, uint48(block.timestamp + 30 days)
        );

        bytes32 privateIntentHash = DCALib.hashPrivateIntent(intent.privateIntent);
        bytes memory swapperSignature = _signIntent(intent);

        intent.privateIntent = PrivateIntent({
            totalAmount: 0,
            exactFrequency: 0,
            numChunks: 0,
            salt: bytes32(0),
            oracleFeeds: new FeedInfo[](0)
        });

        // Cosigner says execAmount = 100e18, but resolved order has inputAmount = 95e18
        DCAOrderCosignerData memory cosignerData = _createCosignerData(nonce, 100e18, 180e18, 0);
        bytes memory cosignerSignature = _signCosignerData(cosignerData);

        uint256 wrongInputAmount = 95e18;
        ResolvedOrder memory resolvedOrder = _createResolvedOrder(intent, wrongInputAmount, 180e18);
        resolvedOrder.info.preExecutionHookData =
            _encodeHookData(intent, swapperSignature, privateIntentHash, cosignerData, cosignerSignature);

        vm.expectRevert(abi.encodeWithSelector(IDCAHook.InputAmountMismatch.selector, wrongInputAmount, 100e18));
        hook.preExecutionHook(filler, resolvedOrder);
    }

    /// @notice Test ZeroInput error for EXACT_OUT when input amount is zero
    function test_revert_zeroInput() public {
        uint256 nonce = 78;

        DCAIntent memory intent = _createExactOutIntent(swapper, nonce);
        vm.prank(swapper);
        IAllowanceTransfer(address(permit2)).approve(
            address(inputToken), address(hook), 1100e18, uint48(block.timestamp + 30 days)
        );

        bytes32 privateIntentHash = DCALib.hashPrivateIntent(intent.privateIntent);
        bytes memory swapperSignature = _signIntent(intent);

        intent.privateIntent = PrivateIntent({
            totalAmount: 0,
            exactFrequency: 0,
            numChunks: 0,
            salt: bytes32(0),
            oracleFeeds: new FeedInfo[](0)
        });

        // Cosigner authorizes EXACT_OUT with execAmount=200e18 (output), limitAmount=110e18 (max input)
        DCAOrderCosignerData memory cosignerData = _createCosignerData(nonce, 200e18, 110e18, 0);
        bytes memory cosignerSignature = _signCosignerData(cosignerData);

        // Resolved order has inputAmount = 0 (intentionally wrong)
        ResolvedOrder memory resolvedOrder = _createResolvedOrder(intent, 0, 200e18);
        resolvedOrder.info.preExecutionHookData =
            _encodeHookData(intent, swapperSignature, privateIntentHash, cosignerData, cosignerSignature);

        vm.expectRevert(abi.encodeWithSelector(IDCAHook.ZeroInput.selector));
        hook.preExecutionHook(filler, resolvedOrder);
    }

    /// @notice Test InputAboveLimit error for EXACT_OUT when input exceeds limitAmount
    function test_revert_inputAboveLimit() public {
        uint256 nonce = 79;

        DCAIntent memory intent = _createExactOutIntent(swapper, nonce);
        vm.prank(swapper);
        IAllowanceTransfer(address(permit2)).approve(
            address(inputToken), address(hook), 1100e18, uint48(block.timestamp + 30 days)
        );

        bytes32 privateIntentHash = DCALib.hashPrivateIntent(intent.privateIntent);
        bytes memory swapperSignature = _signIntent(intent);

        intent.privateIntent = PrivateIntent({
            totalAmount: 0,
            exactFrequency: 0,
            numChunks: 0,
            salt: bytes32(0),
            oracleFeeds: new FeedInfo[](0)
        });

        // Cosigner authorizes EXACT_OUT with execAmount=200e18 (output), limitAmount=110e18 (max input)
        uint256 limitAmount = 110e18;
        DCAOrderCosignerData memory cosignerData = _createCosignerData(nonce, 200e18, limitAmount, 0);
        bytes memory cosignerSignature = _signCosignerData(cosignerData);

        // Resolved order has inputAmount = 120e18, which exceeds limit of 110e18
        uint256 excessiveInput = 120e18;
        ResolvedOrder memory resolvedOrder = _createResolvedOrder(intent, excessiveInput, 200e18);
        resolvedOrder.info.preExecutionHookData =
            _encodeHookData(intent, swapperSignature, privateIntentHash, cosignerData, cosignerSignature);

        vm.expectRevert(abi.encodeWithSelector(IDCAHook.InputAboveLimit.selector, excessiveInput, limitAmount));
        hook.preExecutionHook(filler, resolvedOrder);
    }

    /// @notice Test PriceBelowMin error for EXACT_IN when execution price is below minPrice
    function test_revert_priceBelowMin_exactIn() public {
        uint256 nonce = 80;

        DCAIntent memory intent = _createExactInIntent(swapper, nonce);
        vm.prank(swapper);
        IAllowanceTransfer(address(permit2)).approve(
            address(inputToken), address(hook), 1000e18, uint48(block.timestamp + 30 days)
        );

        bytes32 privateIntentHash = DCALib.hashPrivateIntent(intent.privateIntent);
        bytes memory swapperSignature = _signIntent(intent);

        intent.privateIntent = PrivateIntent({
            totalAmount: 0,
            exactFrequency: 0,
            numChunks: 0,
            salt: bytes32(0),
            oracleFeeds: new FeedInfo[](0)
        });

        // minPrice is 1.5e18 (1.5 output per 1 input)
        // Cosigner authorizes: execAmount=100e18 (input), limitAmount=140e18 (min output)
        // Execution price = 140e18 * 1e18 / 100e18 = 1.4e18, which is below minPrice of 1.5e18
        uint256 execAmount = 100e18;
        uint256 limitAmount = 140e18;
        DCAOrderCosignerData memory cosignerData = _createCosignerData(nonce, execAmount, limitAmount, 0);
        bytes memory cosignerSignature = _signCosignerData(cosignerData);

        ResolvedOrder memory resolvedOrder = _createResolvedOrder(intent, execAmount, limitAmount);
        resolvedOrder.info.preExecutionHookData =
            _encodeHookData(intent, swapperSignature, privateIntentHash, cosignerData, cosignerSignature);

        uint256 executionPrice = 1.4e18;
        uint256 minPrice = 1.5e18;
        vm.expectRevert(abi.encodeWithSelector(IDCAHook.PriceBelowMin.selector, executionPrice, minPrice));
        hook.preExecutionHook(filler, resolvedOrder);
    }

    /// @notice Test PriceBelowMin error for EXACT_OUT when execution price is below minPrice
    function test_revert_priceBelowMin_exactOut() public {
        uint256 nonce = 81;

        DCAIntent memory intent = _createExactOutIntent(swapper, nonce);
        vm.prank(swapper);
        IAllowanceTransfer(address(permit2)).approve(
            address(inputToken), address(hook), 1100e18, uint48(block.timestamp + 30 days)
        );

        bytes32 privateIntentHash = DCALib.hashPrivateIntent(intent.privateIntent);
        bytes memory swapperSignature = _signIntent(intent);

        intent.privateIntent = PrivateIntent({
            totalAmount: 0,
            exactFrequency: 0,
            numChunks: 0,
            salt: bytes32(0),
            oracleFeeds: new FeedInfo[](0)
        });

        // minPrice is 1.5e18 (1.5 output per 1 input)
        // Cosigner authorizes: execAmount=200e18 (exact output), limitAmount=140e18 (max input)
        // Execution price = 200e18 * 1e18 / 140e18 = 1.428...e18, which is below minPrice of 1.5e18
        uint256 execAmount = 200e18;
        uint256 limitAmount = 140e18;
        DCAOrderCosignerData memory cosignerData = _createCosignerData(nonce, execAmount, limitAmount, 0);
        bytes memory cosignerSignature = _signCosignerData(cosignerData);

        // Use actual input of 135e18 (below limit but still bad price)
        ResolvedOrder memory resolvedOrder = _createResolvedOrder(intent, 135e18, execAmount);
        resolvedOrder.info.preExecutionHookData =
            _encodeHookData(intent, swapperSignature, privateIntentHash, cosignerData, cosignerSignature);

        // Price calculation: 200e18 * 1e18 / 140e18 = 1428571428571428571 (approximately 1.428e18)
        uint256 executionPrice = 1428571428571428571;
        uint256 minPrice = 1.5e18;
        vm.expectRevert(abi.encodeWithSelector(IDCAHook.PriceBelowMin.selector, executionPrice, minPrice));
        hook.preExecutionHook(filler, resolvedOrder);
    }

    /// @notice Test AllocationMismatch error for EXACT_IN when recipient receives wrong amount
    function test_revert_allocationMismatch_exactIn() public {
        uint256 nonce = 82;

        // Intent with 90% to swapper, 10% to fee recipient
        DCAIntent memory intent = _createExactInIntentMultipleRecipients(swapper, nonce);
        vm.prank(swapper);
        IAllowanceTransfer(address(permit2)).approve(
            address(inputToken), address(hook), 1000e18, uint48(block.timestamp + 30 days)
        );

        bytes32 privateIntentHash = DCALib.hashPrivateIntent(intent.privateIntent);
        bytes memory swapperSignature = _signIntent(intent);

        intent.privateIntent = PrivateIntent({
            totalAmount: 0,
            exactFrequency: 0,
            numChunks: 0,
            salt: bytes32(0),
            oracleFeeds: new FeedInfo[](0)
        });

        DCAOrderCosignerData memory cosignerData = _createCosignerData(nonce, 100e18, 180e18, 0);
        bytes memory cosignerSignature = _signCosignerData(cosignerData);

        // Create resolved order with WRONG allocation (85% to swapper, 15% to fee instead of 90%/10%)
        address feeRecipient = address(0xFEE);
        ResolvedOrder memory resolvedOrder = _createResolvedOrder(intent, 100e18, 180e18);
        OutputToken[] memory outputs = new OutputToken[](2);
        outputs[0] = OutputToken({token: address(outputToken), amount: 153e18, recipient: swapper}); // 85%
        outputs[1] = OutputToken({token: address(outputToken), amount: 27e18, recipient: feeRecipient}); // 15%
        resolvedOrder.outputs = outputs;

        resolvedOrder.info.preExecutionHookData =
            _encodeHookData(intent, swapperSignature, privateIntentHash, cosignerData, cosignerSignature);

        // Expected for swapper: 180e18 * 9000 / 10000 = 162e18
        // Actual for swapper: 153e18
        vm.expectRevert(abi.encodeWithSelector(IDCAHook.AllocationMismatch.selector, swapper, 153e18, 162e18));
        hook.preExecutionHook(filler, resolvedOrder);
    }

    /// @notice Test AllocationMismatch error for EXACT_OUT when recipient receives wrong amount
    function test_revert_allocationMismatch_exactOut() public {
        uint256 nonce = 83;

        // Create EXACT_OUT intent with multiple recipients
        OutputAllocation[] memory allocations = new OutputAllocation[](2);
        allocations[0] = OutputAllocation({recipient: swapper, basisPoints: 9000});
        allocations[1] = OutputAllocation({recipient: address(0xFEE), basisPoints: 1000});

        PrivateIntent memory privateIntent = PrivateIntent({
            totalAmount: 2000e18,
            exactFrequency: 3600,
            numChunks: 10,
            salt: bytes32(0),
            oracleFeeds: new FeedInfo[](0)
        });

        DCAIntent memory intent = DCAIntent({
            swapper: swapper,
            nonce: nonce,
            chainId: block.chainid,
            hookAddress: address(hook),
            isExactIn: false,
            inputToken: address(inputToken),
            outputToken: address(outputToken),
            cosigner: cosigner,
            minPeriod: 300,
            maxPeriod: 7200,
            minChunkSize: 100e18,
            maxChunkSize: 300e18,
            minPrice: 1.5e18,
            deadline: block.timestamp + 30 days,
            outputAllocations: allocations,
            privateIntent: privateIntent
        });

        vm.prank(swapper);
        IAllowanceTransfer(address(permit2)).approve(
            address(inputToken), address(hook), 1100e18, uint48(block.timestamp + 30 days)
        );

        bytes32 privateIntentHash = DCALib.hashPrivateIntent(intent.privateIntent);
        bytes memory swapperSignature = _signIntent(intent);

        intent.privateIntent = PrivateIntent({
            totalAmount: 0,
            exactFrequency: 0,
            numChunks: 0,
            salt: bytes32(0),
            oracleFeeds: new FeedInfo[](0)
        });

        DCAOrderCosignerData memory cosignerData = _createCosignerData(nonce, 200e18, 110e18, 0);
        bytes memory cosignerSignature = _signCosignerData(cosignerData);

        // Create resolved order with WRONG allocation (swapper gets 175e18 instead of 180e18)
        ResolvedOrder memory resolvedOrder = _createResolvedOrder(intent, 105e18, 200e18);
        OutputToken[] memory outputs = new OutputToken[](2);
        outputs[0] = OutputToken({token: address(outputToken), amount: 175e18, recipient: swapper}); // Wrong
        outputs[1] = OutputToken({token: address(outputToken), amount: 25e18, recipient: address(0xFEE)});
        resolvedOrder.outputs = outputs;

        resolvedOrder.info.preExecutionHookData =
            _encodeHookData(intent, swapperSignature, privateIntentHash, cosignerData, cosignerSignature);

        // Expected for swapper: 200e18 * 9000 / 10000 = 180e18
        // Actual for swapper: 175e18
        vm.expectRevert(abi.encodeWithSelector(IDCAHook.AllocationMismatch.selector, swapper, 175e18, 180e18));
        hook.preExecutionHook(filler, resolvedOrder);
    }

    /// @notice Test InsufficientOutput error for EXACT_IN when total output is below limit
    function test_revert_insufficientOutput() public {
        uint256 nonce = 84;

        DCAIntent memory intent = _createExactInIntent(swapper, nonce);
        vm.prank(swapper);
        IAllowanceTransfer(address(permit2)).approve(
            address(inputToken), address(hook), 1000e18, uint48(block.timestamp + 30 days)
        );

        bytes32 privateIntentHash = DCALib.hashPrivateIntent(intent.privateIntent);
        bytes memory swapperSignature = _signIntent(intent);

        intent.privateIntent = PrivateIntent({
            totalAmount: 0,
            exactFrequency: 0,
            numChunks: 0,
            salt: bytes32(0),
            oracleFeeds: new FeedInfo[](0)
        });

        // Cosigner sets limitAmount = 180e18 (minimum output required)
        DCAOrderCosignerData memory cosignerData = _createCosignerData(nonce, 100e18, 180e18, 0);
        bytes memory cosignerSignature = _signCosignerData(cosignerData);

        // Resolved order only produces 175e18 output (below limit of 180e18)
        uint256 insufficientOutput = 175e18;
        ResolvedOrder memory resolvedOrder = _createResolvedOrder(intent, 100e18, insufficientOutput);
        resolvedOrder.info.preExecutionHookData =
            _encodeHookData(intent, swapperSignature, privateIntentHash, cosignerData, cosignerSignature);

        vm.expectRevert(abi.encodeWithSelector(IDCAHook.InsufficientOutput.selector, insufficientOutput, 180e18));
        hook.preExecutionHook(filler, resolvedOrder);
    }

    /// @notice Test WrongTotalOutput error for EXACT_OUT when total output doesn't match execAmount
    function test_revert_wrongTotalOutput() public {
        uint256 nonce = 85;

        DCAIntent memory intent = _createExactOutIntent(swapper, nonce);
        vm.prank(swapper);
        IAllowanceTransfer(address(permit2)).approve(
            address(inputToken), address(hook), 1100e18, uint48(block.timestamp + 30 days)
        );

        bytes32 privateIntentHash = DCALib.hashPrivateIntent(intent.privateIntent);
        bytes memory swapperSignature = _signIntent(intent);

        intent.privateIntent = PrivateIntent({
            totalAmount: 0,
            exactFrequency: 0,
            numChunks: 0,
            salt: bytes32(0),
            oracleFeeds: new FeedInfo[](0)
        });

        // Cosigner authorizes execAmount = 200e18 (exact output expected)
        DCAOrderCosignerData memory cosignerData = _createCosignerData(nonce, 200e18, 110e18, 0);
        bytes memory cosignerSignature = _signCosignerData(cosignerData);

        // Resolved order produces 195e18 output (doesn't match expected 200e18)
        uint256 wrongOutput = 195e18;
        ResolvedOrder memory resolvedOrder = _createResolvedOrder(intent, 105e18, wrongOutput);
        resolvedOrder.info.preExecutionHookData =
            _encodeHookData(intent, swapperSignature, privateIntentHash, cosignerData, cosignerSignature);

        vm.expectRevert(abi.encodeWithSelector(IDCAHook.WrongTotalOutput.selector, wrongOutput, 200e18));
        hook.preExecutionHook(filler, resolvedOrder);
    }

    // ============ Helper Functions ============

    /// @notice Helper to test static field validation errors (for errors caught before signature verification)
    function _testStaticFieldValidationError(DCAIntent memory intent, uint256 nonce, bytes memory expectedError)
        internal
    {
        vm.prank(swapper);
        IAllowanceTransfer(address(permit2)).approve(
            address(inputToken), address(hook), 1000e18, uint48(block.timestamp + 30 days)
        );

        bytes32 privateIntentHash = DCALib.hashPrivateIntent(intent.privateIntent);
        bytes memory swapperSignature = _signIntent(intent);

        intent.privateIntent = PrivateIntent({
            totalAmount: 0,
            exactFrequency: 0,
            numChunks: 0,
            salt: bytes32(0),
            oracleFeeds: new FeedInfo[](0)
        });

        DCAOrderCosignerData memory cosignerData = _createCosignerData(nonce, 100e18, 180e18, 0);
        bytes memory cosignerSignature = _signCosignerData(cosignerData);

        ResolvedOrder memory resolvedOrder = _createResolvedOrder(intent, 100e18, 180e18);
        resolvedOrder.info.preExecutionHookData =
            _encodeHookData(intent, swapperSignature, privateIntentHash, cosignerData, cosignerSignature);

        vm.expectRevert(expectedError);
        hook.preExecutionHook(filler, resolvedOrder);
    }

    /// @notice Helper to test validation errors with custom resolved order
    function _setupAndTestValidationError(
        DCAIntent memory intent,
        uint256 nonce,
        ResolvedOrder memory resolvedOrder,
        bytes memory expectedError
    ) internal {
        vm.prank(swapper);
        IAllowanceTransfer(address(permit2)).approve(
            address(inputToken), address(hook), 1000e18, uint48(block.timestamp + 30 days)
        );

        bytes32 privateIntentHash = DCALib.hashPrivateIntent(intent.privateIntent);
        bytes memory swapperSignature = _signIntent(intent);

        intent.privateIntent = PrivateIntent({
            totalAmount: 0,
            exactFrequency: 0,
            numChunks: 0,
            salt: bytes32(0),
            oracleFeeds: new FeedInfo[](0)
        });

        DCAOrderCosignerData memory cosignerData = _createCosignerData(nonce, 100e18, 180e18, 0);
        bytes memory cosignerSignature = _signCosignerData(cosignerData);

        resolvedOrder.info.preExecutionHookData =
            _encodeHookData(intent, swapperSignature, privateIntentHash, cosignerData, cosignerSignature);

        vm.expectRevert(expectedError);
        hook.preExecutionHook(filler, resolvedOrder);
    }

    // ============ Intent/Order Creation Helpers ============

    function _createExactInIntent(address _swapper, uint256 _nonce) internal view returns (DCAIntent memory) {
        OutputAllocation[] memory allocations = new OutputAllocation[](1);
        allocations[0] = OutputAllocation({recipient: _swapper, basisPoints: 10000}); // 100% to swapper

        PrivateIntent memory privateIntent = PrivateIntent({
            totalAmount: 1000e18, // Trading 1,000 tokens out of the 10,000 over time
            exactFrequency: 3600, // Trading every hour
            numChunks: 10, // 10 chunks, so 100 tokens per chunk
            salt: bytes32(0),
            oracleFeeds: new FeedInfo[](0)
        });

        return DCAIntent({
            swapper: _swapper,
            nonce: _nonce,
            chainId: block.chainid,
            hookAddress: address(hook),
            isExactIn: true,
            inputToken: address(inputToken),
            outputToken: address(outputToken),
            cosigner: cosigner,
            minPeriod: 300, // Some number less than 1 hour
            maxPeriod: 7200, // Some number greater than 1 hour
            minChunkSize: 50e18, // Some number less than 100 tokens
            maxChunkSize: 200e18, // Some number greater than 100 tokens
            minPrice: 1.5e18, // 1.5 output per 1 input
            deadline: block.timestamp + 30 days,
            outputAllocations: allocations,
            privateIntent: privateIntent
        });
    }

    function _createExactOutIntent(address _swapper, uint256 _nonce) internal view returns (DCAIntent memory) {
        OutputAllocation[] memory allocations = new OutputAllocation[](1);
        allocations[0] = OutputAllocation({recipient: _swapper, basisPoints: 10000}); // 100% to swapper

        PrivateIntent memory privateIntent = PrivateIntent({
            totalAmount: 2000e18, // Total output for EXACT_OUT
            exactFrequency: 3600,
            numChunks: 10, // 200 tokens per chunk
            salt: bytes32(0),
            oracleFeeds: new FeedInfo[](0)
        });

        return DCAIntent({
            swapper: _swapper,
            nonce: _nonce,
            chainId: block.chainid,
            hookAddress: address(hook),
            isExactIn: false,
            inputToken: address(inputToken),
            outputToken: address(outputToken),
            cosigner: cosigner,
            minPeriod: 300,
            maxPeriod: 7200,
            minChunkSize: 100e18, // something less than 200
            maxChunkSize: 300e18, // something greater than 200
            minPrice: 1.5e18, // 1.5 output per 1 input
            deadline: block.timestamp + 30 days,
            outputAllocations: allocations,
            privateIntent: privateIntent
        });
    }

    function _createExactInIntentMultipleRecipients(address _swapper, uint256 _nonce)
        internal
        view
        returns (DCAIntent memory)
    {
        OutputAllocation[] memory allocations = new OutputAllocation[](2);
        allocations[0] = OutputAllocation({recipient: _swapper, basisPoints: 9000}); // 90% to swapper
        allocations[1] = OutputAllocation({recipient: address(0xFEE), basisPoints: 1000}); // 10% fee

        PrivateIntent memory privateIntent = PrivateIntent({
            totalAmount: 1000e18,
            exactFrequency: 3600,
            numChunks: 10,
            salt: bytes32(0),
            oracleFeeds: new FeedInfo[](0)
        });

        return DCAIntent({
            swapper: _swapper,
            nonce: _nonce,
            chainId: block.chainid,
            hookAddress: address(hook),
            isExactIn: true,
            inputToken: address(inputToken),
            outputToken: address(outputToken),
            cosigner: cosigner,
            minPeriod: 300,
            maxPeriod: 7200,
            minChunkSize: 50e18,
            maxChunkSize: 200e18,
            minPrice: 1.5e18,
            deadline: block.timestamp + 30 days,
            outputAllocations: allocations,
            privateIntent: privateIntent
        });
    }

    function _createResolvedOrder(DCAIntent memory intent, uint256 inputAmount, uint256 outputAmount)
        internal
        view
        returns (ResolvedOrder memory)
    {
        OutputToken[] memory outputs = new OutputToken[](1);
        outputs[0] = OutputToken({token: address(outputToken), amount: outputAmount, recipient: intent.swapper});

        return ResolvedOrder({
            info: OrderInfo({
                reactor: IReactor(reactor),
                swapper: intent.swapper,
                nonce: intent.nonce,
                deadline: intent.deadline,
                preExecutionHook: IPreExecutionHook(address(hook)),
                preExecutionHookData: "", // empty but will be filled in after creation
                postExecutionHook: IPostExecutionHook(address(0)),
                postExecutionHookData: "",
                auctionResolver: IAuctionResolver(address(0))
            }),
            input: InputToken({token: ERC20(address(inputToken)), amount: inputAmount, maxAmount: inputAmount}),
            outputs: outputs,
            sig: "",
            hash: bytes32(0),
            auctionResolver: address(0)
        });
    }

    function _createResolvedOrderMultipleRecipients(
        DCAIntent memory intent,
        uint256 inputAmount,
        uint256 totalOutput,
        address feeRecipient
    ) internal view returns (ResolvedOrder memory) {
        OutputToken[] memory outputs = new OutputToken[](2);
        // 90% to swapper, 10% to fee recipient
        outputs[0] =
            OutputToken({token: address(outputToken), amount: (totalOutput * 9000) / 10000, recipient: intent.swapper});
        outputs[1] =
            OutputToken({token: address(outputToken), amount: (totalOutput * 1000) / 10000, recipient: feeRecipient});

        return ResolvedOrder({
            info: OrderInfo({
                reactor: IReactor(reactor),
                swapper: intent.swapper,
                nonce: intent.nonce,
                deadline: intent.deadline,
                preExecutionHook: IPreExecutionHook(address(hook)),
                preExecutionHookData: "",
                postExecutionHook: IPostExecutionHook(address(0)),
                postExecutionHookData: "",
                auctionResolver: IAuctionResolver(address(0))
            }),
            input: InputToken({token: ERC20(address(inputToken)), amount: inputAmount, maxAmount: inputAmount}),
            outputs: outputs,
            sig: "",
            hash: bytes32(0),
            auctionResolver: address(0)
        });
    }

    /// @notice Helper: Swapper signs the DCA intent (with full private data)
    function _signIntent(DCAIntent memory intent) internal view returns (bytes memory) {
        bytes32 intentHash = DCALib.hash(intent);
        bytes32 swapperDigest = DCALib.digest(hook.domainSeparator(), intentHash);
        return _sign(swapperPrivateKey, swapperDigest);
    }

    /// @notice Helper: Create cosigner authorization data for a specific execution
    function _createCosignerData(uint256 nonce, uint256 execAmount, uint256 limitAmount, uint96 orderNonce)
        internal
        view
        returns (DCAOrderCosignerData memory)
    {
        return DCAOrderCosignerData({
            swapper: swapper,
            nonce: uint96(nonce),
            execAmount: uint160(execAmount),
            orderNonce: orderNonce,
            limitAmount: uint160(limitAmount)
        });
    }

    /// @notice Helper: Cosigner signs the execution authorization
    function _signCosignerData(DCAOrderCosignerData memory cosignerData) internal view returns (bytes memory) {
        bytes32 cosignerStructHash = DCALib.hashCosignerData(cosignerData);
        bytes32 cosignerDigest = DCALib.digest(hook.domainSeparator(), cosignerStructHash);
        return _sign(cosignerPrivateKey, cosignerDigest);
    }

    /// @notice Helper: Encode all hook data (intent should already have private data zeroed out)
    function _encodeHookData(
        DCAIntent memory intent,
        bytes memory swapperSignature,
        bytes32 privateIntentHash,
        DCAOrderCosignerData memory cosignerData,
        bytes memory cosignerSignature
    ) internal pure returns (bytes memory) {
        // Create empty permit data (using Permit2 allowance instead)
        PermitData memory permitData = PermitData({
            hasPermit: false,
            permitSingle: IAllowanceTransfer.PermitSingle({
                details: IAllowanceTransfer.PermitDetails({token: address(0), amount: 0, expiration: 0, nonce: 0}),
                spender: address(0),
                sigDeadline: 0
            }),
            signature: ""
        });

        return abi.encode(intent, swapperSignature, privateIntentHash, cosignerData, cosignerSignature, permitData);
    }

    function _sign(uint256 privateKey, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
