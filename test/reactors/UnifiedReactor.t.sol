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
import {PriorityOrder, PriorityInput, PriorityOutput, PriorityCosignerData, PriorityOrderLib} from "../../src/lib/PriorityOrderLib.sol";
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

        OrderInfo memory info = OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 1000)
            .withValidationContract(IValidationCallback(validationContract));

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

        (SignedOrder memory signedOrder, bytes32 orderHash) =
            createPriorityOrder(false, address(0));

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

        (SignedOrder memory signedOrder, bytes32 orderHash) =
            createPriorityOrder(true, address(0)); // true = useAllowanceTransfer

        vm.expectEmit(true, true, true, true, address(reactor));
        emit Fill(orderHash, address(fillContract), swapper, 0);

        fillContract.execute(signedOrder);

        assertEq(tokenIn.balanceOf(swapper), 0);
        assertEq(tokenIn.balanceOf(address(fillContract)), inputAmount);
        assertEq(tokenOut.balanceOf(swapper), outputAmount);
        assertEq(tokenOut.balanceOf(address(fillContract)), 0);
    }

    /// @dev Test batch execution with mixed transfer types
    /* DISABLED - needs refactoring for new architecture
    function test_executeBatchMixedTransferTypes() public {
        setupTokensForTest();

        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;

        // Setup for 2 orders
        tokenIn.mint(address(swapper), inputAmount * 2);
        tokenOut.mint(address(fillContract), outputAmount * 2);

        // First order: SignatureTransfer
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);
        (SignedOrder memory order1,) = createUnifiedOrder(address(limitResolver), false, address(0));

        // Second order: AllowanceTransfer
        vm.startPrank(swapper);
        tokenIn.approve(address(permit2), type(uint256).max);
        IAllowanceTransfer(address(permit2)).approve(
            address(tokenIn), address(unifiedReactor), uint160(inputAmount), uint48(block.timestamp + 1000)
        );
        vm.stopPrank();

        UnifiedOrder memory order2 = UnifiedOrder({
            info: UnifiedOrderInfo({
                baseInfo: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 1000)
                    .withValidationData(hex"01"), // AllowanceTransfer flag
                useAllowanceTransfer: true,
                auctionResolver: address(limitResolver)
            }),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(address(tokenOut), outputAmount, swapper)
        });

        bytes memory sig2 = signOrder(swapperPrivateKey, address(permit2), order2);
        SignedOrder memory signedOrder2 = SignedOrder(abi.encode(order2), sig2);

        SignedOrder[] memory orders = new SignedOrder[](2);
        orders[0] = order1;
        orders[1] = signedOrder2;

        fillContract.executeBatch(orders);

        assertEq(tokenIn.balanceOf(swapper), 0);
        assertEq(tokenIn.balanceOf(address(fillContract)), inputAmount * 2);
        assertEq(tokenOut.balanceOf(swapper), outputAmount * 2);
        assertEq(tokenOut.balanceOf(address(fillContract)), 0);
    }
    */

    /* DISABLED - needs refactoring
    function test_executeDCAOrderWithValidation() public {
        setupTokensForTest();

        uint256 inputAmount = 500e18; // 500 tokens per chunk
        uint256 outputAmount = 0.2 ether;

        tokenIn.mint(address(swapper), inputAmount);
        tokenOut.mint(address(fillContract), outputAmount);

        // Setup AllowanceTransfer
        vm.startPrank(swapper);
        tokenIn.approve(address(permit2), type(uint256).max);
        IAllowanceTransfer(address(permit2)).approve(
            address(tokenIn),
            address(unifiedReactor),
            uint160(inputAmount * 10), // Allow for multiple executions
            uint48(block.timestamp + 30 days)
        );
        vm.stopPrank();

        // Create DCA intent
        IDCARegistry.DCAIntent memory intent =
            createBasicDCAIntent(address(tokenIn), address(tokenOut), cosigner, swapper, 0);
        intent.minChunkSize = 100e18;
        intent.maxChunkSize = 1000e18;

        // Create cosigner data
        IDCARegistry.DCAOrderCosignerData memory cosignerData =
            createBasicCosignerData(inputAmount, outputAmount, bytes32(uint256(1)));

        // Create validation data with signatures
        IDCARegistry.DCAValidationData memory validationData =
            createSignedDCAValidationData(intent, cosignerData, swapperPrivateKey, cosignerPrivateKey, dcaRegistry);

        // Encode validation data with AllowanceTransfer flag
        bytes memory encodedValidationData = abi.encodePacked(hex"01", abi.encode(validationData));

        // Create order with DCA validation
        UnifiedOrder memory order = UnifiedOrder({
            info: UnifiedOrderInfo({
                baseInfo: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 1000)
                    .withValidationContract(IValidationCallback(address(dcaRegistry))).withValidationData(encodedValidationData),
                useAllowanceTransfer: true,
                auctionResolver: address(limitResolver)
            }),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(address(tokenOut), outputAmount, swapper)
        });

        bytes32 orderHash = order.hash();
        bytes memory sig = signOrder(swapperPrivateKey, address(permit2), order);
        SignedOrder memory signedOrder = SignedOrder(abi.encode(order), sig);

        vm.expectEmit(true, true, true, true, address(reactor));
        emit Fill(orderHash, address(fillContract), swapper, 0);

        fillContract.execute(signedOrder);

        assertEq(tokenIn.balanceOf(swapper), 0);
        assertEq(tokenIn.balanceOf(address(fillContract)), inputAmount);
        assertEq(tokenOut.balanceOf(swapper), outputAmount);
        assertEq(tokenOut.balanceOf(address(fillContract)), 0);

        // Verify DCA state was updated
        IDCARegistry.DCAExecutionState memory state = dcaRegistry.getExecutionState(dcaRegistry.hashDCAIntent(intent));
        assertEq(state.executedChunks, 1);
        assertEq(state.totalInputExecuted, inputAmount);
    }
    */

    /* DISABLED - needs refactoring 
    function test_DCAValidationFailures() public {
        setupTokensForTest();

        uint256 inputAmount = 500e18;
        uint256 outputAmount = 0.2 ether;

        tokenIn.mint(address(swapper), inputAmount);
        tokenOut.mint(address(fillContract), outputAmount);

        // Setup AllowanceTransfer
        vm.startPrank(swapper);
        tokenIn.approve(address(permit2), type(uint256).max);
        IAllowanceTransfer(address(permit2)).approve(
            address(tokenIn), address(unifiedReactor), uint160(inputAmount), uint48(block.timestamp + 30 days)
        );
        vm.stopPrank();

        // Test 1: Invalid cosigner signature
        IDCARegistry.DCAIntent memory intent =
            createBasicDCAIntent(address(tokenIn), address(tokenOut), cosigner, swapper, 0);

        IDCARegistry.DCAOrderCosignerData memory cosignerData =
            createBasicCosignerData(inputAmount, outputAmount, bytes32(uint256(1)));

        // Create validation data with wrong cosigner signature
        bytes32 intentHash = dcaRegistry.hashDCAIntent(intent);
        IDCARegistry.DCAValidationData memory validationData = IDCARegistry.DCAValidationData({
            intent: intent,
            signature: signDCAIntent(intent, swapperPrivateKey, dcaRegistry),
            cosignerData: cosignerData,
            cosignature: signCosignerData(intentHash, cosignerData, swapperPrivateKey) // Wrong key
        });

        bytes memory encodedValidationData = abi.encodePacked(hex"01", abi.encode(validationData));

        UnifiedOrder memory order = UnifiedOrder({
            info: UnifiedOrderInfo({
                baseInfo: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 1000)
                    .withValidationContract(IValidationCallback(address(dcaRegistry))).withValidationData(encodedValidationData),
                useAllowanceTransfer: true,
                auctionResolver: address(limitResolver)
            }),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(address(tokenOut), outputAmount, swapper)
        });

        bytes memory sig = signOrder(swapperPrivateKey, address(permit2), order);
        SignedOrder memory signedOrder = SignedOrder(abi.encode(order), sig);

        vm.expectRevert(DCARegistry.InvalidCosignature.selector);
        fillContract.execute(signedOrder);

        // Test 2: Chunk size too small
        intent.minChunkSize = 1000e18; // Minimum is higher than actual

        validationData =
            createSignedDCAValidationData(intent, cosignerData, swapperPrivateKey, cosignerPrivateKey, dcaRegistry);

        encodedValidationData = abi.encodePacked(hex"01", abi.encode(validationData));

        order.info.baseInfo = OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(
            block.timestamp + 1000
        ).withValidationContract(IValidationCallback(address(dcaRegistry))).withValidationData(encodedValidationData);

        sig = signOrder(swapperPrivateKey, address(permit2), order);
        signedOrder = SignedOrder(abi.encode(order), sig);

        vm.expectRevert(DCARegistry.InvalidDCAChunkSize.selector);
        fillContract.execute(signedOrder);
    }
    */

    /* DISABLED - needs refactoring
    function test_differentAuctionResolvers() public {
        setupTokensForTest();

        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;

        address[3] memory resolvers = [address(limitResolver), address(dutchResolver), address(priorityResolver)];

        for (uint256 i = 0; i < resolvers.length; i++) {
            tokenIn.mint(address(swapper), inputAmount);
            tokenOut.mint(address(fillContract), outputAmount);
            tokenIn.forceApprove(swapper, address(permit2), inputAmount);

            (SignedOrder memory signedOrder,) = createUnifiedOrder(resolvers[i], false, address(0));

            fillContract.execute(signedOrder);

            assertEq(tokenIn.balanceOf(swapper), 0);
            assertEq(tokenOut.balanceOf(swapper), outputAmount);
        }
    }
    */
}