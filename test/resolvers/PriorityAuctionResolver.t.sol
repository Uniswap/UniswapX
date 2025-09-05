// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {DeployPermit2} from "../util/DeployPermit2.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {SignedOrder, ResolvedOrderV2, OrderInfoV2, InputToken, OutputToken} from "../../src/base/ReactorStructs.sol";
import {ReactorEvents} from "../../src/base/ReactorEvents.sol";
import {UnifiedReactor} from "../../src/reactors/UnifiedReactor.sol";
import {PriorityAuctionResolver} from "../../src/resolvers/PriorityAuctionResolver.sol";
import {
    PriorityOrderV2,
    PriorityOrderLibV2,
    PriorityInput,
    PriorityOutput,
    PriorityCosignerData
} from "../../src/lib/PriorityOrderLib.sol";
import {PriorityFeeLib} from "../../src/lib/PriorityFeeLib.sol";
import {CosignerLib} from "../../src/lib/CosignerLib.sol";
import {OrderInfoBuilderV2} from "../util/OrderInfoBuilderV2.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {MockFillContractV2} from "../util/mock/MockFillContractV2.sol";
import {MockFeeController} from "../util/mock/MockFeeController.sol";
import {TokenTransferHook} from "../../src/hooks/TokenTransferHook.sol";

contract PriorityAuctionResolverTest is ReactorEvents, Test, PermitSignature, DeployPermit2 {
    using OrderInfoBuilderV2 for OrderInfoV2;
    using PriorityOrderLibV2 for PriorityOrderV2;
    using PriorityFeeLib for PriorityInput;
    using PriorityFeeLib for PriorityOutput;
    using PriorityFeeLib for PriorityOutput[];

    uint256 constant ONE = 10 ** 18;
    uint256 constant cosignerPrivateKey = 0x99999999;
    address internal constant PROTOCOL_FEE_OWNER = address(1);

    MockERC20 tokenIn;
    MockERC20 tokenOut;
    MockERC20 tokenOut2;
    MockFillContractV2 fillContract;
    IPermit2 permit2;
    TokenTransferHook tokenTransferHook;
    MockFeeController feeController;
    address feeRecipient;
    UnifiedReactor reactor;
    PriorityAuctionResolver resolver;
    uint256 swapperPrivateKey;
    address swapper;
    address cosigner;

    function setUp() public {
        tokenIn = new MockERC20("Input", "IN", 18);
        tokenOut = new MockERC20("Output", "OUT", 18);
        tokenOut2 = new MockERC20("Output2", "OUT2", 18);
        swapperPrivateKey = 0x12341234;
        swapper = vm.addr(swapperPrivateKey);
        cosigner = vm.addr(cosignerPrivateKey);
        permit2 = IPermit2(deployPermit2());
        feeRecipient = makeAddr("feeRecipient");
        feeController = new MockFeeController(feeRecipient);
        tokenTransferHook = new TokenTransferHook(permit2);

        // Deploy UnifiedReactor and PriorityAuctionResolver
        reactor = new UnifiedReactor(permit2, PROTOCOL_FEE_OWNER);
        resolver = new PriorityAuctionResolver(permit2);

        // Deploy fill contract
        fillContract = new MockFillContractV2(address(reactor));

        // Provide tokens for tests
        tokenIn.mint(address(swapper), ONE * 100);
        tokenOut.mint(address(fillContract), ONE * 100);

        // Provide ETH to fill contract for native transfers
        vm.deal(address(fillContract), type(uint256).max);
    }

    /// @dev Create and sign a PriorityOrderV2 for UnifiedReactor
    function signAndEncodeOrder(PriorityOrderV2 memory order)
        internal
        view
        returns (SignedOrder memory signedOrder, bytes32 orderHash)
    {
        orderHash = order.hash();

        // Sign the order with swapper's key
        bytes memory sig = signOrder(swapperPrivateKey, address(permit2), order);

        // Encode the order data for the resolver
        bytes memory orderData = abi.encode(order);

        // Wrap with resolver address for UnifiedReactor
        bytes memory encodedOrder = abi.encode(address(resolver), orderData);

        signedOrder = SignedOrder(encodedOrder, sig);
    }

    /// @dev Helper to cosign an order
    function cosignOrder(bytes32 orderHash, PriorityCosignerData memory cosignerData)
        internal
        view
        returns (bytes memory cosignature)
    {
        bytes32 msgHash = keccak256(abi.encodePacked(orderHash, block.chainid, abi.encode(cosignerData)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(cosignerPrivateKey, msgHash);
        cosignature = bytes.concat(r, s, bytes1(v));
    }

    /// @dev Test a basic order when output priority fee is non zero
    function testExecuteWithOutputPriorityFee() public {
        uint256 priorityFee = 100 wei;
        vm.txGasPrice(priorityFee);

        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;
        uint256 inputMpsPerPriorityFeeWei = 0;
        uint256 outputMpsPerPriorityFeeWei = 1; // exact input
        uint256 deadline = block.timestamp + 1000;

        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        PriorityOutput[] memory outputs = new PriorityOutput[](1);
        outputs[0] = PriorityOutput({
            token: address(tokenOut),
            amount: outputAmount,
            mpsPerPriorityFeeWei: outputMpsPerPriorityFeeWei,
            recipient: swapper
        });

        uint256 scaledOutputAmount = outputs[0].scale(priorityFee).amount;

        PriorityCosignerData memory cosignerData = PriorityCosignerData({auctionTargetBlock: block.number});

        PriorityOrderV2 memory order = PriorityOrderV2({
            info: OrderInfoBuilderV2.init(address(reactor)).withSwapper(swapper).withDeadline(deadline).withPreExecutionHook(
                tokenTransferHook
            ),
            cosigner: cosigner,
            auctionStartBlock: block.number,
            baselinePriorityFeeWei: 0,
            input: PriorityInput({token: tokenIn, amount: inputAmount, mpsPerPriorityFeeWei: inputMpsPerPriorityFeeWei}),
            outputs: outputs,
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);

        (SignedOrder memory signedOrder, bytes32 orderHash) = signAndEncodeOrder(order);

        uint256 swapperInputBalanceStart = tokenIn.balanceOf(address(swapper));
        uint256 swapperOutputBalanceStart = tokenOut.balanceOf(address(swapper));

        vm.expectEmit(true, true, true, true, address(reactor));
        emit Fill(orderHash, address(fillContract), swapper, order.info.nonce);

        // Execute order through UnifiedReactor
        fillContract.execute(signedOrder);
        vm.snapshotGasLastCall("UnifiedReactor_PriorityOutputFee");

        assertEq(tokenOut.balanceOf(address(swapper)), swapperOutputBalanceStart + scaledOutputAmount);
        assertEq(tokenIn.balanceOf(address(swapper)), swapperInputBalanceStart - inputAmount);
    }

    /// @dev Test with baseline priority fee
    function testExecuteWithOutputPriorityFeeAndBaselinePriorityFee() public {
        uint256 baselinePriorityFeeWei = 1 gwei;
        uint256 priorityFee = baselinePriorityFeeWei + 100 wei;
        vm.txGasPrice(priorityFee);

        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;
        uint256 inputMpsPerPriorityFeeWei = 0;
        uint256 outputMpsPerPriorityFeeWei = 1;
        uint256 deadline = block.timestamp + 1000;

        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        PriorityOutput[] memory outputs = new PriorityOutput[](1);
        outputs[0] = PriorityOutput({
            token: address(tokenOut),
            amount: outputAmount,
            mpsPerPriorityFeeWei: outputMpsPerPriorityFeeWei,
            recipient: swapper
        });

        // Should only scale by the difference
        uint256 scaledOutputAmount = outputs[0].scale(priorityFee - baselinePriorityFeeWei).amount;

        PriorityCosignerData memory cosignerData = PriorityCosignerData({auctionTargetBlock: block.number});

        PriorityOrderV2 memory order = PriorityOrderV2({
            info: OrderInfoBuilderV2.init(address(reactor)).withSwapper(swapper).withDeadline(deadline).withPreExecutionHook(
                tokenTransferHook
            ),
            cosigner: cosigner,
            auctionStartBlock: block.number,
            baselinePriorityFeeWei: baselinePriorityFeeWei,
            input: PriorityInput({token: tokenIn, amount: inputAmount, mpsPerPriorityFeeWei: inputMpsPerPriorityFeeWei}),
            outputs: outputs,
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);

        (SignedOrder memory signedOrder, bytes32 orderHash) = signAndEncodeOrder(order);

        uint256 swapperInputBalanceStart = tokenIn.balanceOf(address(swapper));
        uint256 swapperOutputBalanceStart = tokenOut.balanceOf(address(swapper));

        vm.expectEmit(true, true, true, true, address(reactor));
        emit Fill(orderHash, address(fillContract), swapper, order.info.nonce);

        fillContract.execute(signedOrder);
        vm.snapshotGasLastCall("UnifiedReactor_PriorityOutputFeeWithBaseline");

        assertEq(tokenOut.balanceOf(address(swapper)), swapperOutputBalanceStart + scaledOutputAmount);
        assertEq(tokenIn.balanceOf(address(swapper)), swapperInputBalanceStart - inputAmount);
    }

    /// @dev Test when priority fee is less than baseline (no scaling)
    function testExecuteWithOutputPriorityFeeLessThanBaseline() public {
        uint256 baselinePriorityFeeWei = 1 gwei;
        uint256 priorityFee = baselinePriorityFeeWei - 1;
        vm.txGasPrice(priorityFee);

        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;
        uint256 inputMpsPerPriorityFeeWei = 0;
        uint256 outputMpsPerPriorityFeeWei = 1;
        uint256 deadline = block.timestamp + 1000;

        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        PriorityOutput[] memory outputs = new PriorityOutput[](1);
        outputs[0] = PriorityOutput({
            token: address(tokenOut),
            amount: outputAmount,
            mpsPerPriorityFeeWei: outputMpsPerPriorityFeeWei,
            recipient: swapper
        });

        PriorityCosignerData memory cosignerData = PriorityCosignerData({auctionTargetBlock: block.number});

        PriorityOrderV2 memory order = PriorityOrderV2({
            info: OrderInfoBuilderV2.init(address(reactor)).withSwapper(swapper).withDeadline(deadline).withPreExecutionHook(
                tokenTransferHook
            ),
            cosigner: cosigner,
            auctionStartBlock: block.number,
            baselinePriorityFeeWei: baselinePriorityFeeWei,
            input: PriorityInput({token: tokenIn, amount: inputAmount, mpsPerPriorityFeeWei: inputMpsPerPriorityFeeWei}),
            outputs: outputs,
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);

        (SignedOrder memory signedOrder,) = signAndEncodeOrder(order);

        uint256 swapperInputBalanceStart = tokenIn.balanceOf(address(swapper));
        uint256 swapperOutputBalanceStart = tokenOut.balanceOf(address(swapper));

        fillContract.execute(signedOrder);

        // No scaling should be applied since priority fee < baseline
        assertEq(tokenOut.balanceOf(address(swapper)), swapperOutputBalanceStart + outputAmount);
        assertEq(tokenIn.balanceOf(address(swapper)), swapperInputBalanceStart - inputAmount);
    }

    /// @dev Test with input priority fee scaling
    function testExecuteWithInputPriorityFee() public {
        uint256 priorityFee = 100 wei;
        vm.txGasPrice(priorityFee);

        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;
        uint256 inputMpsPerPriorityFeeWei = 1; // exact output
        uint256 outputMpsPerPriorityFeeWei = 0;
        uint256 deadline = block.timestamp + 1000;

        tokenIn.forceApprove(swapper, address(permit2), inputAmount * 2);

        PriorityInput memory input =
            PriorityInput({token: tokenIn, amount: inputAmount, mpsPerPriorityFeeWei: inputMpsPerPriorityFeeWei});

        PriorityOutput[] memory outputs = new PriorityOutput[](1);
        outputs[0] = PriorityOutput({
            token: address(tokenOut),
            amount: outputAmount,
            mpsPerPriorityFeeWei: outputMpsPerPriorityFeeWei,
            recipient: swapper
        });

        uint256 scaledInputAmount = input.scale(priorityFee).amount;

        PriorityCosignerData memory cosignerData = PriorityCosignerData({auctionTargetBlock: block.number});

        PriorityOrderV2 memory order = PriorityOrderV2({
            info: OrderInfoBuilderV2.init(address(reactor)).withSwapper(swapper).withDeadline(deadline).withPreExecutionHook(
                tokenTransferHook
            ),
            cosigner: cosigner,
            auctionStartBlock: block.number,
            baselinePriorityFeeWei: 0,
            input: input,
            outputs: outputs,
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);

        (SignedOrder memory signedOrder, bytes32 orderHash) = signAndEncodeOrder(order);

        uint256 swapperInputBalanceStart = tokenIn.balanceOf(address(swapper));
        uint256 swapperOutputBalanceStart = tokenOut.balanceOf(address(swapper));

        vm.expectEmit(true, true, true, true, address(reactor));
        emit Fill(orderHash, address(fillContract), swapper, order.info.nonce);

        fillContract.execute(signedOrder);
        vm.snapshotGasLastCall("UnifiedReactor_PriorityInputFee");

        assertEq(tokenIn.balanceOf(address(swapper)), swapperInputBalanceStart - scaledInputAmount);
        assertEq(tokenOut.balanceOf(address(swapper)), swapperOutputBalanceStart + outputAmount);
    }

    /// @dev Test cosigner override of auction start block
    function testExecuteWithOverrideAuctionStartBlock() public {
        PriorityOutput[] memory outputs = new PriorityOutput[](1);
        outputs[0] = PriorityOutput({token: address(tokenOut), amount: 0, mpsPerPriorityFeeWei: 0, recipient: swapper});

        PriorityCosignerData memory cosignerData = PriorityCosignerData({auctionTargetBlock: block.number + 5});

        PriorityOrderV2 memory order = PriorityOrderV2({
            info: OrderInfoBuilderV2.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 1000)
                .withPreExecutionHook(tokenTransferHook),
            cosigner: cosigner,
            auctionStartBlock: block.number + 10,
            baselinePriorityFeeWei: 0,
            input: PriorityInput({token: tokenIn, amount: 0, mpsPerPriorityFeeWei: 0}),
            outputs: outputs,
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);

        (SignedOrder memory signedOrder, bytes32 orderHash) = signAndEncodeOrder(order);

        vm.roll(block.number + 5);

        vm.expectEmit(true, true, true, true, address(reactor));
        emit Fill(orderHash, address(fillContract), swapper, order.info.nonce);

        fillContract.execute(signedOrder);
        vm.snapshotGasLastCall("UnifiedReactor_OverrideAuctionTargetBlock");
    }

    /// @dev Test execution after auction start block
    function testExecuteAfterAuctionStartBlock() public {
        PriorityOutput[] memory outputs = new PriorityOutput[](1);
        outputs[0] = PriorityOutput({token: address(tokenOut), amount: 0, mpsPerPriorityFeeWei: 0, recipient: swapper});

        PriorityCosignerData memory cosignerData = PriorityCosignerData({auctionTargetBlock: block.number});

        PriorityOrderV2 memory order = PriorityOrderV2({
            info: OrderInfoBuilderV2.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 1000)
                .withPreExecutionHook(tokenTransferHook),
            cosigner: cosigner,
            auctionStartBlock: block.number,
            baselinePriorityFeeWei: 0,
            input: PriorityInput({token: tokenIn, amount: 0, mpsPerPriorityFeeWei: 0}),
            outputs: outputs,
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);

        (SignedOrder memory signedOrder, bytes32 orderHash) = signAndEncodeOrder(order);

        vm.roll(block.number + 1);

        vm.expectEmit(true, true, true, true, address(reactor));
        emit Fill(orderHash, address(fillContract), swapper, order.info.nonce);

        fillContract.execute(signedOrder);
    }

    /// @dev Test with invalid cosigner auctionTargetBlock still works at auctionStartBlock
    function testExecuteInvalidCosignerAuctionTargetBlock() public {
        PriorityOutput[] memory outputs = new PriorityOutput[](1);
        outputs[0] = PriorityOutput({token: address(tokenOut), amount: 0, mpsPerPriorityFeeWei: 0, recipient: swapper});

        PriorityCosignerData memory cosignerData = PriorityCosignerData({auctionTargetBlock: block.number + 1});

        PriorityOrderV2 memory order = PriorityOrderV2({
            info: OrderInfoBuilderV2.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 1000)
                .withPreExecutionHook(tokenTransferHook),
            cosigner: cosigner,
            auctionStartBlock: block.number,
            baselinePriorityFeeWei: 0,
            input: PriorityInput({token: tokenIn, amount: 0, mpsPerPriorityFeeWei: 0}),
            outputs: outputs,
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);

        (SignedOrder memory signedOrder, bytes32 orderHash) = signAndEncodeOrder(order);

        vm.expectEmit(true, true, true, true, address(reactor));
        emit Fill(orderHash, address(fillContract), swapper, order.info.nonce);

        fillContract.execute(signedOrder);
    }

    /// @dev Test execution after auctionStartBlock with invalid cosignature
    function testExecuteAfterAuctionStartBlockWithInvalidCosignature() public {
        address wrongCosigner = makeAddr("wrongCosigner");

        PriorityOutput[] memory outputs = new PriorityOutput[](1);
        outputs[0] = PriorityOutput({token: address(tokenOut), amount: 0, mpsPerPriorityFeeWei: 0, recipient: swapper});

        PriorityCosignerData memory cosignerData = PriorityCosignerData({auctionTargetBlock: block.number});

        PriorityOrderV2 memory order = PriorityOrderV2({
            info: OrderInfoBuilderV2.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 1000)
                .withPreExecutionHook(tokenTransferHook),
            cosigner: wrongCosigner,
            auctionStartBlock: block.number + 1,
            baselinePriorityFeeWei: 0,
            input: PriorityInput({token: tokenIn, amount: 0, mpsPerPriorityFeeWei: 0}),
            outputs: outputs,
            cosignerData: cosignerData,
            cosignature: bytes.concat(keccak256("invalidSignature"), keccak256("invalidSignature"), hex"33")
        });

        (SignedOrder memory signedOrder, bytes32 orderHash) = signAndEncodeOrder(order);

        vm.roll(block.number + 1);

        vm.expectEmit(true, true, true, true, address(reactor));
        emit Fill(orderHash, address(fillContract), swapper, order.info.nonce);

        fillContract.execute(signedOrder);
    }

    /// @dev Test revert when both input and output scale with priority fee
    function testRevertsWithInputOutputScaling() public {
        uint256 mpsPerPriorityFeeWei = 1;

        PriorityOutput[] memory outputs = new PriorityOutput[](1);
        outputs[0] = PriorityOutput({
            token: address(tokenOut),
            amount: 0,
            mpsPerPriorityFeeWei: mpsPerPriorityFeeWei,
            recipient: swapper
        });

        PriorityCosignerData memory cosignerData = PriorityCosignerData({auctionTargetBlock: block.number});

        PriorityOrderV2 memory order = PriorityOrderV2({
            info: OrderInfoBuilderV2.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 1000)
                .withPreExecutionHook(tokenTransferHook),
            cosigner: cosigner,
            auctionStartBlock: block.number,
            baselinePriorityFeeWei: 0,
            input: PriorityInput({token: tokenIn, amount: 0, mpsPerPriorityFeeWei: mpsPerPriorityFeeWei}),
            outputs: outputs,
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);

        (SignedOrder memory signedOrder,) = signAndEncodeOrder(order);

        vm.expectRevert(PriorityAuctionResolver.InputOutputScaling.selector);
        fillContract.execute(signedOrder);
    }

    /// @dev Test revert before auction start block
    function testRevertsBeforeAuctionStartBlock() public {
        PriorityOutput[] memory outputs = new PriorityOutput[](1);
        outputs[0] = PriorityOutput({token: address(tokenOut), amount: 0, mpsPerPriorityFeeWei: 0, recipient: swapper});

        PriorityCosignerData memory cosignerData = PriorityCosignerData({auctionTargetBlock: block.number + 1});

        PriorityOrderV2 memory order = PriorityOrderV2({
            info: OrderInfoBuilderV2.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 1000)
                .withPreExecutionHook(tokenTransferHook),
            cosigner: cosigner,
            auctionStartBlock: block.number + 1,
            baselinePriorityFeeWei: 0,
            input: PriorityInput({token: tokenIn, amount: 0, mpsPerPriorityFeeWei: 0}),
            outputs: outputs,
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);

        (SignedOrder memory signedOrder,) = signAndEncodeOrder(order);

        vm.expectRevert(PriorityAuctionResolver.OrderNotFillable.selector);
        fillContract.execute(signedOrder);
    }

    /// @dev Test revert before cosigned auction target block
    function testRevertsBeforeCosignedAuctionTargetBlock() public {
        PriorityOutput[] memory outputs = new PriorityOutput[](1);
        outputs[0] = PriorityOutput({token: address(tokenOut), amount: 0, mpsPerPriorityFeeWei: 0, recipient: swapper});

        PriorityCosignerData memory cosignerData = PriorityCosignerData({auctionTargetBlock: block.number + 1});

        PriorityOrderV2 memory order = PriorityOrderV2({
            info: OrderInfoBuilderV2.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 1000)
                .withPreExecutionHook(tokenTransferHook),
            cosigner: cosigner,
            auctionStartBlock: block.number + 2,
            baselinePriorityFeeWei: 0,
            input: PriorityInput({token: tokenIn, amount: 0, mpsPerPriorityFeeWei: 0}),
            outputs: outputs,
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);

        (SignedOrder memory signedOrder,) = signAndEncodeOrder(order);

        vm.expectRevert(PriorityAuctionResolver.OrderNotFillable.selector);
        fillContract.execute(signedOrder);
    }

    /// @dev Test revert with wrong cosigner
    function testRevertsWrongCosigner() public {
        address wrongCosigner = makeAddr("wrongCosigner");

        PriorityOutput[] memory outputs = new PriorityOutput[](1);
        outputs[0] = PriorityOutput({token: address(tokenOut), amount: 0, mpsPerPriorityFeeWei: 0, recipient: swapper});

        PriorityCosignerData memory cosignerData = PriorityCosignerData({auctionTargetBlock: block.number});

        PriorityOrderV2 memory order = PriorityOrderV2({
            info: OrderInfoBuilderV2.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 1000)
                .withPreExecutionHook(tokenTransferHook),
            cosigner: wrongCosigner,
            auctionStartBlock: block.number + 1,
            baselinePriorityFeeWei: 0,
            input: PriorityInput({token: tokenIn, amount: 0, mpsPerPriorityFeeWei: 0}),
            outputs: outputs,
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);

        (SignedOrder memory signedOrder,) = signAndEncodeOrder(order);

        vm.expectRevert(CosignerLib.InvalidCosignature.selector);
        fillContract.execute(signedOrder);
    }

    /// @dev Test revert with invalid cosignature
    function testRevertsInvalidCosignature() public {
        PriorityOutput[] memory outputs = new PriorityOutput[](1);
        outputs[0] = PriorityOutput({token: address(tokenOut), amount: 0, mpsPerPriorityFeeWei: 0, recipient: swapper});

        PriorityCosignerData memory cosignerData = PriorityCosignerData({auctionTargetBlock: block.number});

        PriorityOrderV2 memory order = PriorityOrderV2({
            info: OrderInfoBuilderV2.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 1000)
                .withPreExecutionHook(tokenTransferHook),
            cosigner: cosigner,
            auctionStartBlock: block.number + 1,
            baselinePriorityFeeWei: 0,
            input: PriorityInput({token: tokenIn, amount: 0, mpsPerPriorityFeeWei: 0}),
            outputs: outputs,
            cosignerData: cosignerData,
            cosignature: bytes.concat(keccak256("invalidSignature"), keccak256("invalidSignature"), hex"33")
        });

        (SignedOrder memory signedOrder,) = signAndEncodeOrder(order);

        vm.expectRevert(CosignerLib.InvalidCosignature.selector);
        fillContract.execute(signedOrder);
    }

    /// @dev Test revert with invalid chain ID in cosignature
    function testRevertsInvalidChainIdCosignature() public {
        uint256 invalidChainId = 0;

        PriorityOutput[] memory outputs = new PriorityOutput[](1);
        outputs[0] = PriorityOutput({token: address(tokenOut), amount: 0, mpsPerPriorityFeeWei: 0, recipient: swapper});

        PriorityCosignerData memory cosignerData = PriorityCosignerData({auctionTargetBlock: block.number});

        PriorityOrderV2 memory order = PriorityOrderV2({
            info: OrderInfoBuilderV2.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 1000)
                .withPreExecutionHook(tokenTransferHook),
            cosigner: cosigner,
            auctionStartBlock: block.number + 1,
            baselinePriorityFeeWei: 0,
            input: PriorityInput({token: tokenIn, amount: 0, mpsPerPriorityFeeWei: 0}),
            outputs: outputs,
            cosignerData: cosignerData,
            cosignature: bytes("")
        });

        // Sign with invalid chain ID
        bytes32 msgHash = keccak256(abi.encodePacked(order.hash(), invalidChainId, abi.encode(cosignerData)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(cosignerPrivateKey, msgHash);
        order.cosignature = bytes.concat(r, s, bytes1(v));

        (SignedOrder memory signedOrder,) = signAndEncodeOrder(order);

        vm.expectRevert(CosignerLib.InvalidCosignature.selector);
        fillContract.execute(signedOrder);
    }

    /// @dev Test revert when tx gas price is below base fee
    function testRevertsInvalidTxGasPrice() public {
        vm.txGasPrice(0);
        vm.fee(1);

        PriorityOutput[] memory outputs = new PriorityOutput[](1);
        outputs[0] = PriorityOutput({token: address(tokenOut), amount: 0, mpsPerPriorityFeeWei: 0, recipient: swapper});

        PriorityCosignerData memory cosignerData = PriorityCosignerData({auctionTargetBlock: block.number});

        PriorityOrderV2 memory order = PriorityOrderV2({
            info: OrderInfoBuilderV2.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 1000)
                .withPreExecutionHook(tokenTransferHook),
            cosigner: cosigner,
            auctionStartBlock: block.number,
            baselinePriorityFeeWei: 0,
            input: PriorityInput({token: tokenIn, amount: 0, mpsPerPriorityFeeWei: 0}),
            outputs: outputs,
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);

        (SignedOrder memory signedOrder,) = signAndEncodeOrder(order);

        vm.expectRevert(PriorityAuctionResolver.InvalidGasPrice.selector);
        fillContract.execute(signedOrder);
    }

    /// @dev Test revert when nonce is already used
    function testCheckPermit2Nonce() public {
        // Mark nonce as used
        uint256 nonce = 0;
        uint256 wordPos = uint248(nonce >> 8);
        uint256 bitPos = uint8(nonce);
        uint256 bit = 1 << bitPos;

        vm.prank(swapper);
        permit2.invalidateUnorderedNonces(wordPos, bit);

        PriorityOutput[] memory outputs = new PriorityOutput[](1);
        outputs[0] = PriorityOutput({token: address(tokenOut), amount: 0, mpsPerPriorityFeeWei: 0, recipient: swapper});

        PriorityCosignerData memory cosignerData = PriorityCosignerData({auctionTargetBlock: block.number});

        PriorityOrderV2 memory order = PriorityOrderV2({
            info: OrderInfoBuilderV2.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 1000)
                .withNonce(nonce),
            cosigner: cosigner,
            auctionStartBlock: block.number,
            baselinePriorityFeeWei: 0,
            input: PriorityInput({token: tokenIn, amount: 0, mpsPerPriorityFeeWei: 0}),
            outputs: outputs,
            cosignerData: cosignerData,
            cosignature: bytes("")
        });

        (SignedOrder memory signedOrder,) = signAndEncodeOrder(order);

        vm.expectRevert(PriorityAuctionResolver.OrderAlreadyFilled.selector);
        fillContract.execute(signedOrder);
    }

    /// @dev Test multiple outputs with priority fee scaling
    function testExecuteMultipleOutputsWithPriorityFee() public {
        uint256 priorityFee = 100 wei;
        vm.txGasPrice(priorityFee);

        uint256 inputAmount = 1 ether;
        uint256 outputAmount1 = 0.5 ether;
        uint256 outputAmount2 = 0.3 ether;
        uint256 deadline = block.timestamp + 1000;

        tokenIn.forceApprove(swapper, address(permit2), inputAmount);
        // Mint enough tokens to cover scaled amounts
        tokenOut.mint(address(fillContract), outputAmount1 * 2);
        tokenOut2.mint(address(fillContract), outputAmount2 * 2);

        PriorityOutput[] memory outputs = new PriorityOutput[](2);
        outputs[0] = PriorityOutput({
            token: address(tokenOut),
            amount: outputAmount1,
            mpsPerPriorityFeeWei: 1,
            recipient: swapper
        });
        outputs[1] = PriorityOutput({
            token: address(tokenOut2),
            amount: outputAmount2,
            mpsPerPriorityFeeWei: 2,
            recipient: swapper
        });

        uint256 scaledOutputAmount1 = outputs[0].scale(priorityFee).amount;
        uint256 scaledOutputAmount2 = outputs[1].scale(priorityFee).amount;

        PriorityCosignerData memory cosignerData = PriorityCosignerData({auctionTargetBlock: block.number});

        PriorityOrderV2 memory order = PriorityOrderV2({
            info: OrderInfoBuilderV2.init(address(reactor)).withSwapper(swapper).withDeadline(deadline).withPreExecutionHook(
                tokenTransferHook
            ),
            cosigner: cosigner,
            auctionStartBlock: block.number,
            baselinePriorityFeeWei: 0,
            input: PriorityInput({token: tokenIn, amount: inputAmount, mpsPerPriorityFeeWei: 0}),
            outputs: outputs,
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);

        (SignedOrder memory signedOrder, bytes32 orderHash) = signAndEncodeOrder(order);

        uint256 swapperInputBalanceStart = tokenIn.balanceOf(address(swapper));
        uint256 swapperOutputBalanceStart = tokenOut.balanceOf(address(swapper));
        uint256 swapperOutput2BalanceStart = tokenOut2.balanceOf(address(swapper));

        vm.expectEmit(true, true, true, true, address(reactor));
        emit Fill(orderHash, address(fillContract), swapper, order.info.nonce);

        fillContract.execute(signedOrder);

        assertEq(tokenIn.balanceOf(address(swapper)), swapperInputBalanceStart - inputAmount);
        assertEq(tokenOut.balanceOf(address(swapper)), swapperOutputBalanceStart + scaledOutputAmount1);
        assertEq(tokenOut2.balanceOf(address(swapper)), swapperOutput2BalanceStart + scaledOutputAmount2);
    }

    /// @dev Test permit2 nonce check
    function testExecuteSignatureReplay() public {
        uint256 inputAmount = 0.1 ether;
        uint256 outputAmount = 0.1 ether;
        uint256 deadline = block.timestamp + 1000;

        tokenIn.forceApprove(swapper, address(permit2), inputAmount * 2);

        PriorityOutput[] memory outputs = new PriorityOutput[](1);
        outputs[0] = PriorityOutput({
            token: address(tokenOut),
            amount: outputAmount,
            mpsPerPriorityFeeWei: 0,
            recipient: swapper
        });

        PriorityCosignerData memory cosignerData = PriorityCosignerData({auctionTargetBlock: block.number});

        PriorityOrderV2 memory order = PriorityOrderV2({
            info: OrderInfoBuilderV2.init(address(reactor)).withSwapper(swapper).withDeadline(deadline).withPreExecutionHook(
                tokenTransferHook
            ),
            cosigner: cosigner,
            auctionStartBlock: block.number,
            baselinePriorityFeeWei: 0,
            input: PriorityInput({token: tokenIn, amount: inputAmount, mpsPerPriorityFeeWei: 0}),
            outputs: outputs,
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);

        (SignedOrder memory signedOrder,) = signAndEncodeOrder(order);

        // Execute once successfully
        fillContract.execute(signedOrder);

        vm.expectRevert(PriorityAuctionResolver.OrderAlreadyFilled.selector);
        fillContract.execute(signedOrder);
    }
}
