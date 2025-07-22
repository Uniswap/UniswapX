// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {DeployPermit2} from "../util/DeployPermit2.sol";
import {UnifiedReactor} from "../../src/reactors/UnifiedReactor.sol";
import {BaseReactor} from "../../src/reactors/BaseReactor.sol";
import {OrderInfo, InputToken, OutputToken, SignedOrder, ResolvedOrder} from "../../src/base/ReactorStructs.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {MockFillContract} from "../util/mock/MockFillContract.sol";
import {MockFeeController} from "../util/mock/MockFeeController.sol";
import {MockValidationContract} from "../util/mock/MockValidationContract.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {ReactorEvents} from "../../src/base/ReactorEvents.sol";
import {BaseReactorTest} from "../base/BaseReactor.t.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {PriorityAuctionResolver} from "../../src/resolvers/PriorityAuctionResolver.sol";
import {
    PriorityOrder,
    PriorityInput,
    PriorityOutput,
    PriorityCosignerData,
    PriorityOrderLib
} from "../../src/lib/PriorityOrderLib.sol";
import {CosignerLib} from "../../src/lib/CosignerLib.sol";
import {DCARegistry} from "../../src/validation/DCARegistry.sol";
import {DCAIntentSignature} from "../util/DCAIntentSignature.sol";
import {IDCARegistry} from "../../src/interfaces/IDCARegistry.sol";
import {IValidationCallback} from "../../src/interfaces/IValidationCallback.sol";

contract UnifiedReactorTest is PermitSignature, DeployPermit2, BaseReactorTest, DCAIntentSignature {
    using OrderInfoBuilder for OrderInfo;
    using PriorityOrderLib for PriorityOrder;

    UnifiedReactor unifiedReactor;
    PriorityAuctionResolver priorityResolver;
    DCARegistry dcaRegistry;

    uint256 cosignerPrivateKey = 0x99999999;
    address cosigner;

    /// @dev Struct to avoid stack too deep in DCA order creation
    struct DCAOrderVars {
        IDCARegistry.DCAIntent intent;
        IDCARegistry.DCAOrderCosignerData cosignerData;
        IDCARegistry.DCAValidationData validationData;
        bytes encodedValidationData;
        PriorityOutput[] outputs;
        PriorityCosignerData priorityCosignerData;
        PriorityOrder order;
        bytes priorityOrderBytes;
        bytes encodedOrder;
        bytes signature;
    }

    function name() public pure override returns (string memory) {
        return "UnifiedReactor";
    }

    /// @notice Helper to cosign priority orders following PriorityOrderReactor pattern
    function cosignOrder(bytes32 orderHash, PriorityCosignerData memory cosignerData)
        private
        view
        returns (bytes memory sig)
    {
        bytes32 msgHash = keccak256(abi.encodePacked(orderHash, block.chainid, abi.encode(cosignerData)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(cosignerPrivateKey, msgHash);
        sig = bytes.concat(r, s, bytes1(v));
    }

    function setUp() public {
        cosigner = vm.addr(cosignerPrivateKey);

        // Deploy resolvers
        priorityResolver = new PriorityAuctionResolver(permit2);

        // Deploy DCA registry
        dcaRegistry = new DCARegistry();

        // Setup validation contract
        additionalValidationContract.setValid(true);

        // Provide ETH to fill contract for native transfers
        vm.deal(address(fillContract), type(uint256).max);

        // Set unifiedReactor reference
        unifiedReactor = UnifiedReactor(payable(address(reactor)));
    }

    function createReactor() public override returns (BaseReactor) {
        return new UnifiedReactor(permit2, PROTOCOL_FEE_OWNER);
    }

    /// @dev Helper to set up tokens for a test
    function setupTokensForTest() internal {
        tokenIn = new MockERC20("Fresh Input", "FIN", 18);
        tokenOut = new MockERC20("Fresh Output", "FOUT", 18);
        tokenOut2 = new MockERC20("Fresh Output2", "FOUT2", 18);
    }

    /// @dev Create and sign a PriorityOrder following PriorityOrderReactor.t.sol pattern
    function createAndSignOrder(ResolvedOrder memory request)
        public
        view
        override
        returns (SignedOrder memory signedOrder, bytes32 orderHash)
    {
        PriorityOutput[] memory outputs = new PriorityOutput[](request.outputs.length);
        for (uint256 i = 0; i < request.outputs.length; i++) {
            outputs[i] = PriorityOutput({
                token: request.outputs[i].token,
                amount: request.outputs[i].amount,
                mpsPerPriorityFeeWei: 0,
                recipient: request.outputs[i].recipient
            });
        }

        PriorityCosignerData memory cosignerData = PriorityCosignerData({auctionTargetBlock: block.number});

        PriorityOrder memory order = PriorityOrder({
            info: request.info,
            cosigner: vm.addr(cosignerPrivateKey),
            auctionStartBlock: block.number,
            baselinePriorityFeeWei: 0,
            input: PriorityInput({token: request.input.token, amount: request.input.amount, mpsPerPriorityFeeWei: 0}),
            outputs: outputs,
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);

        // Encode for UnifiedReactor: (address resolver, bytes orderData)
        bytes memory priorityOrderBytes = abi.encode(order);
        bytes memory encodedOrder = abi.encode(address(priorityResolver), priorityOrderBytes);

        orderHash = order.hash();
        bytes memory signature = signOrder(swapperPrivateKey, address(permit2), order);

        return (SignedOrder(encodedOrder, signature), orderHash);
    }

    /// @dev Create a PriorityOrder with specific resolver and transfer type
    function createPriorityOrder(bool useAllowanceTransfer, address validationContract)
        internal
        returns (SignedOrder memory signedOrder, bytes32 orderHash)
    {
        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;

        OrderInfo memory info = OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(
            block.timestamp + 1000
        ).withValidationContract(IValidationCallback(validationContract));

        if (useAllowanceTransfer) {
            info.additionalValidationData = abi.encodePacked(uint8(0x01));
        }

        PriorityOutput[] memory outputs = new PriorityOutput[](1);
        outputs[0] = PriorityOutput({
            token: address(tokenOut),
            amount: outputAmount,
            mpsPerPriorityFeeWei: 0,
            recipient: swapper
        });

        PriorityCosignerData memory cosignerData = PriorityCosignerData({auctionTargetBlock: block.number});

        PriorityOrder memory order = PriorityOrder({
            info: info,
            cosigner: vm.addr(cosignerPrivateKey),
            auctionStartBlock: block.number,
            baselinePriorityFeeWei: 0,
            input: PriorityInput({token: tokenIn, amount: inputAmount, mpsPerPriorityFeeWei: 0}),
            outputs: outputs,
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);

        // Encode for UnifiedReactor: (address resolver, bytes orderData)
        bytes memory priorityOrderBytes = abi.encode(order);
        bytes memory encodedOrder = abi.encode(address(priorityResolver), priorityOrderBytes);

        orderHash = order.hash();
        bytes memory signature = signOrder(swapperPrivateKey, address(permit2), order);

        return (SignedOrder(encodedOrder, signature), orderHash);
    }

    /// @dev Test execution with priority order resolver
    function test_executePriorityOrder() public {
        setupTokensForTest();

        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;

        tokenIn.mint(address(swapper), inputAmount);
        tokenOut.mint(address(fillContract), outputAmount);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        (SignedOrder memory signedOrder, bytes32 orderHash) = createPriorityOrder(false, address(0));

        vm.expectEmit(true, true, true, true, address(reactor));
        emit Fill(orderHash, address(fillContract), swapper, 0);

        fillContract.execute(signedOrder);

        assertEq(tokenIn.balanceOf(swapper), 0);
        assertEq(tokenIn.balanceOf(address(fillContract)), inputAmount);
        assertEq(tokenOut.balanceOf(swapper), outputAmount);
        assertEq(tokenOut.balanceOf(address(fillContract)), 0);
    }

    /// @dev Test execution with empty auction resolver reverts
    function test_emptyAuctionResolverReverts() public {
        setupTokensForTest();

        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;

        tokenIn.mint(address(swapper), inputAmount);
        tokenOut.mint(address(fillContract), outputAmount);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        // Create order with empty resolver address following proper pattern
        PriorityOutput[] memory outputs = new PriorityOutput[](1);
        outputs[0] = PriorityOutput({
            token: address(tokenOut),
            amount: outputAmount,
            mpsPerPriorityFeeWei: 0,
            recipient: swapper
        });

        PriorityCosignerData memory cosignerData = PriorityCosignerData({auctionTargetBlock: block.number});

        PriorityOrder memory order = PriorityOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 1000),
            cosigner: vm.addr(cosignerPrivateKey),
            auctionStartBlock: block.number,
            baselinePriorityFeeWei: 0,
            input: PriorityInput({token: tokenIn, amount: inputAmount, mpsPerPriorityFeeWei: 0}),
            outputs: outputs,
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);

        bytes memory priorityOrderBytes = abi.encode(order);
        bytes memory encodedOrder = abi.encode(address(0), priorityOrderBytes); // Empty resolver
        bytes memory signature = signOrder(swapperPrivateKey, address(permit2), order);

        SignedOrder memory signedOrder = SignedOrder(encodedOrder, signature);

        vm.expectRevert(UnifiedReactor.EmptyAuctionResolver.selector);
        fillContract.execute(signedOrder);
    }

    /// @dev Create a DCA order with specific parameters
    function createDCAOrder(uint256 inputAmount, uint256 outputAmount, bytes32 dcaNonce, uint256 intentNonce)
        internal
        returns (SignedOrder memory signedOrder, bytes32 intentHash)
    {
        // Use struct hack to avoid stack too deep
        DCAOrderVars memory vars;

        // Create DCA intent
        vars.intent = createBasicDCAIntent(address(tokenIn), address(tokenOut), cosigner, swapper, intentNonce);
        vars.intent.minChunkSize = 100e18;
        vars.intent.maxChunkSize = 1000e18;
        vars.intent.minFrequency = 1 hours;
        vars.intent.maxFrequency = 24 hours;
        vars.intent.minOutputAmount = outputAmount; // Set minimum output for this execution

        // Create cosigner data
        vars.cosignerData = createBasicCosignerData(inputAmount, outputAmount, dcaNonce);

        // Create validation data with signatures
        vars.validationData = createSignedDCAValidationData(
            vars.intent, vars.cosignerData, swapperPrivateKey, cosignerPrivateKey, dcaRegistry
        );

        // Encode validation data with AllowanceTransfer flag
        vars.encodedValidationData = abi.encodePacked(uint8(0x01), abi.encode(vars.validationData));

        // Create PriorityOrder with DCA validation
        vars.outputs = new PriorityOutput[](1);
        vars.outputs[0] = PriorityOutput({
            token: address(tokenOut),
            amount: outputAmount,
            mpsPerPriorityFeeWei: 0,
            recipient: swapper
        });

        vars.priorityCosignerData = PriorityCosignerData({auctionTargetBlock: block.number});

        vars.order = PriorityOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 1000)
                .withValidationContract(IValidationCallback(address(dcaRegistry))).withValidationData(
                vars.encodedValidationData
            ),
            cosigner: cosigner,
            auctionStartBlock: block.number,
            baselinePriorityFeeWei: 0,
            input: PriorityInput({token: tokenIn, amount: inputAmount, mpsPerPriorityFeeWei: 0}),
            outputs: vars.outputs,
            cosignerData: vars.priorityCosignerData,
            cosignature: bytes("")
        });
        vars.order.cosignature = cosignOrder(vars.order.hash(), vars.priorityCosignerData);

        // Encode for UnifiedReactor
        vars.priorityOrderBytes = abi.encode(vars.order);
        vars.encodedOrder = abi.encode(address(priorityResolver), vars.priorityOrderBytes);
        vars.signature = signOrder(swapperPrivateKey, address(permit2), vars.order);

        signedOrder = SignedOrder(vars.encodedOrder, vars.signature);
        intentHash = dcaRegistry.hashDCAIntent(vars.intent);
    }

    /// @dev Test DCA execution with two chunks
    function test_executeDCAOrderTwoChunks() public {
        setupTokensForTest();

        uint256 chunk1Amount = 500e18; // 500 tokens per chunk
        uint256 chunk2Amount = 300e18; // 300 tokens for second chunk
        uint256 outputAmount1 = 0.2 ether;
        uint256 outputAmount2 = 0.12 ether;
        uint256 totalInputAmount = chunk1Amount + chunk2Amount;
        uint256 intentNonce = 1; // Same intent for both chunks

        // Mint tokens for both chunks
        tokenIn.mint(address(swapper), totalInputAmount);
        tokenOut.mint(address(fillContract), outputAmount1 + outputAmount2);

        // Setup AllowanceTransfer for both chunks
        vm.startPrank(swapper);
        tokenIn.approve(address(permit2), type(uint256).max);
        IAllowanceTransfer(address(permit2)).approve(
            address(tokenIn), address(unifiedReactor), uint160(totalInputAmount), uint48(block.timestamp + 30 days)
        );
        vm.stopPrank();

        // Create the DCA intent once (will be auto-registered on first execution)
        IDCARegistry.DCAIntent memory intent =
            createBasicDCAIntent(address(tokenIn), address(tokenOut), cosigner, swapper, intentNonce);
        intent.minChunkSize = 100e18;
        intent.maxChunkSize = 1000e18;
        intent.minFrequency = 1 hours;
        intent.maxFrequency = 24 hours;
        intent.minOutputAmount = 0.1 ether; // User requires at least 0.1 ETH output per execution

        bytes32 intentHash = dcaRegistry.hashDCAIntent(intent);
        bytes memory intentSignature = signDCAIntent(intent, swapperPrivateKey, dcaRegistry);

        // Execute first chunk - this will auto-register the DCA intent
        (SignedOrder memory signedOrder1,) = createDCAOrderWithRegisteredIntent(
            intent, intentSignature, chunk1Amount, outputAmount1, bytes32(uint256(1))
        );

        fillContract.execute(signedOrder1);

        // Verify first chunk execution
        assertEq(tokenIn.balanceOf(swapper), chunk2Amount); // Remaining tokens
        assertEq(tokenIn.balanceOf(address(fillContract)), chunk1Amount);
        assertEq(tokenOut.balanceOf(swapper), outputAmount1);

        // Verify DCA state after first chunk
        IDCARegistry.DCAExecutionState memory state = dcaRegistry.getExecutionState(intentHash);
        assertEq(state.executedChunks, 1);
        assertEq(state.totalInputExecuted, chunk1Amount);
        assertEq(state.lastExecutionTime, block.timestamp);

        // Wait to satisfy frequency constraints (move forward 2 hours)
        vm.warp(block.timestamp + 2 hours);

        // Execute second chunk using the same intent (now registered)
        (SignedOrder memory signedOrder2,) = createDCAOrderWithRegisteredIntent(
            intent, intentSignature, chunk2Amount, outputAmount2, bytes32(uint256(2))
        );

        fillContract.execute(signedOrder2);

        // Verify final state
        assertEq(tokenIn.balanceOf(swapper), 0); // All tokens used
        assertEq(tokenIn.balanceOf(address(fillContract)), totalInputAmount);
        assertEq(tokenOut.balanceOf(swapper), outputAmount1 + outputAmount2);

        // Verify final DCA state
        state = dcaRegistry.getExecutionState(intentHash);
        assertEq(state.executedChunks, 2);
        assertEq(state.totalInputExecuted, totalInputAmount);
    }

    /// @dev Create a DCA order using a pre-registered intent
    function createDCAOrderWithRegisteredIntent(
        IDCARegistry.DCAIntent memory intent,
        bytes memory intentSignature,
        uint256 inputAmount,
        uint256 outputAmount,
        bytes32 dcaNonce
    ) internal returns (SignedOrder memory signedOrder, bytes32 intentHash) {
        DCAOrderVars memory vars;

        vars.intent = intent;

        // Create cosigner data for this specific order
        vars.cosignerData = createBasicCosignerData(inputAmount, outputAmount, dcaNonce);

        // Create validation data with pre-signed intent
        vars.validationData = IDCARegistry.DCAValidationData({
            intent: vars.intent,
            signature: intentSignature, // Reuse the signed intent
            cosignerData: vars.cosignerData,
            cosignature: signCosignerData(dcaRegistry.hashDCAIntent(vars.intent), vars.cosignerData, cosignerPrivateKey)
        });

        // Encode validation data with AllowanceTransfer flag
        vars.encodedValidationData = abi.encodePacked(uint8(0x01), abi.encode(vars.validationData));

        // Create PriorityOrder with DCA validation
        vars.outputs = new PriorityOutput[](1);
        vars.outputs[0] = PriorityOutput({
            token: address(tokenOut),
            amount: outputAmount,
            mpsPerPriorityFeeWei: 0,
            recipient: swapper
        });

        vars.priorityCosignerData = PriorityCosignerData({auctionTargetBlock: block.number});

        vars.order = PriorityOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 1000)
                .withValidationContract(IValidationCallback(address(dcaRegistry))).withValidationData(
                vars.encodedValidationData
            ),
            cosigner: cosigner,
            auctionStartBlock: block.number,
            baselinePriorityFeeWei: 0,
            input: PriorityInput({token: tokenIn, amount: inputAmount, mpsPerPriorityFeeWei: 0}),
            outputs: vars.outputs,
            cosignerData: vars.priorityCosignerData,
            cosignature: bytes("")
        });
        vars.order.cosignature = cosignOrder(vars.order.hash(), vars.priorityCosignerData);

        // Encode for UnifiedReactor
        vars.priorityOrderBytes = abi.encode(vars.order);
        vars.encodedOrder = abi.encode(address(priorityResolver), vars.priorityOrderBytes);
        vars.signature = signOrder(swapperPrivateKey, address(permit2), vars.order);

        signedOrder = SignedOrder(vars.encodedOrder, vars.signature);
        intentHash = dcaRegistry.hashDCAIntent(vars.intent);
    }

    /// @dev Test that DCA validation enforces user's minimum output amount
    function test_DCAFloorPriceEnforced() public {
        setupTokensForTest();

        uint256 inputAmount = 500e18;
        uint256 userMinOutput = 0.2 ether; // User requires at least 0.2 ETH
        uint256 lowOutput = 0.1 ether; // Cosigner tries to authorize only 0.1 ETH
        uint256 intentNonce = 1;

        // Mint tokens
        tokenIn.mint(address(swapper), inputAmount);
        tokenOut.mint(address(fillContract), lowOutput);

        // Setup AllowanceTransfer
        vm.startPrank(swapper);
        tokenIn.approve(address(permit2), type(uint256).max);
        IAllowanceTransfer(address(permit2)).approve(
            address(tokenIn), address(unifiedReactor), uint160(inputAmount), uint48(block.timestamp + 30 days)
        );
        vm.stopPrank();

        // Create DCA intent with minimum output requirement
        IDCARegistry.DCAIntent memory intent =
            createBasicDCAIntent(address(tokenIn), address(tokenOut), cosigner, swapper, intentNonce);
        intent.minChunkSize = 100e18;
        intent.maxChunkSize = 1000e18;
        intent.minFrequency = 1 hours;
        intent.maxFrequency = 24 hours;
        intent.minOutputAmount = userMinOutput; // User signed intent requires 0.2 ETH minimum

        bytes memory intentSignature = signDCAIntent(intent, swapperPrivateKey, dcaRegistry);

        // Try to create order with output below user's minimum
        (SignedOrder memory signedOrder,) =
            createDCAOrderWithRegisteredIntent(intent, intentSignature, inputAmount, lowOutput, bytes32(uint256(1)));

        // Should revert with DCAFloorPriceNotMet because 0.1 ETH < 0.2 ETH minimum
        vm.expectRevert(DCARegistry.DCAFloorPriceNotMet.selector);
        fillContract.execute(signedOrder);
    }

    /// @dev Test AllowanceTransfer mode
    function test_executeWithAllowanceTransfer() public {
        setupTokensForTest();

        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;

        tokenIn.mint(address(swapper), inputAmount);
        tokenOut.mint(address(fillContract), outputAmount);

        // Approve reactor for AllowanceTransfer
        vm.startPrank(swapper);
        tokenIn.approve(address(permit2), type(uint256).max);
        IAllowanceTransfer(address(permit2)).approve(
            address(tokenIn), address(unifiedReactor), uint160(inputAmount), uint48(block.timestamp + 1000)
        );
        vm.stopPrank();

        (SignedOrder memory signedOrder, bytes32 orderHash) = createPriorityOrder(true, address(0)); // true = useAllowanceTransfer

        vm.expectEmit(true, true, true, true, address(reactor));
        emit Fill(orderHash, address(fillContract), swapper, 0);

        fillContract.execute(signedOrder);

        assertEq(tokenIn.balanceOf(swapper), 0);
        assertEq(tokenIn.balanceOf(address(fillContract)), inputAmount);
        assertEq(tokenOut.balanceOf(swapper), outputAmount);
        assertEq(tokenOut.balanceOf(address(fillContract)), 0);
    }
}
