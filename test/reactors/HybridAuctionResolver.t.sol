// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {DeployPermit2} from "../util/DeployPermit2.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {UnifiedReactor} from "../../src/reactors/UnifiedReactor.sol";
import {HybridAuctionResolver} from "../../src/resolvers/HybridAuctionResolver.sol";
import {ReactorEvents} from "../../src/base/ReactorEvents.sol";
import {ResolvedOrderV2, SignedOrder, OrderInfoV2, InputToken, OutputToken} from "../../src/base/ReactorStructs.sol";
import {
    HybridOrder,
    HybridInput,
    HybridOutput,
    HybridCosignerData,
    HybridOrderLib
} from "../../src/lib/HybridOrderLib.sol";
import {OrderInfoBuilderV2} from "../util/OrderInfoBuilderV2.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {MockFillContractV2} from "../util/mock/MockFillContractV2.sol";
import {TokenTransferHook} from "../../src/hooks/TokenTransferHook.sol";
import {ArrayBuilder} from "../util/ArrayBuilder.sol";
import {NATIVE} from "../../src/lib/CurrencyLibrary.sol";
import {PriceCurveLib, PriceCurveElement} from "lib/tribunal/src/lib/PriceCurveLib.sol";
import {CosignerLib} from "../../src/lib/CosignerLib.sol";

contract HybridAuctionResolverTest is ReactorEvents, Test, PermitSignature, DeployPermit2 {
    using OrderInfoBuilderV2 for OrderInfoV2;
    using HybridOrderLib for HybridOrder;
    using PriceCurveLib for uint256;
    using ArrayBuilder for uint256[];

    uint256 constant ONE = 10 ** 18;
    address internal constant PROTOCOL_FEE_OWNER = address(1);

    MockERC20 tokenIn;
    MockERC20 tokenOut;
    MockFillContractV2 fillContract;
    TokenTransferHook tokenTransferHook;
    IPermit2 permit2;
    UnifiedReactor reactor;
    HybridAuctionResolver resolver;

    uint256 swapperPrivateKey;
    address swapper;
    uint256 cosignerPrivateKey;
    address cosigner;

    function setUp() public {
        tokenIn = new MockERC20("Input", "IN", 18);
        tokenOut = new MockERC20("Output", "OUT", 18);

        swapperPrivateKey = 0x12341234;
        swapper = vm.addr(swapperPrivateKey);
        cosignerPrivateKey = 0x56785678;
        cosigner = vm.addr(cosignerPrivateKey);

        permit2 = IPermit2(deployPermit2());
        tokenTransferHook = new TokenTransferHook(permit2);

        // Deploy UnifiedReactor and Resolver
        reactor = new UnifiedReactor(permit2, PROTOCOL_FEE_OWNER);
        resolver = new HybridAuctionResolver();

        // Deploy fill contract
        fillContract = new MockFillContractV2(address(reactor));

        // Provide ETH to fill contract for native transfers
        vm.deal(address(fillContract), type(uint256).max);
    }

    /// @dev Create a signed order for HybridAuctionResolver
    function signAndEncodeOrder(HybridOrder memory order)
        public
        view
        returns (SignedOrder memory signedOrder, bytes32 orderHash)
    {
        orderHash = order.hash();

        // Sign the order
        bytes memory sig = signOrder(swapperPrivateKey, address(permit2), order);

        // Encode the order data for the resolver
        bytes memory orderData = abi.encode(order);

        // Wrap with resolver address for UnifiedReactor
        bytes memory encodedOrder = abi.encode(address(resolver), orderData);

        signedOrder = SignedOrder(encodedOrder, sig);
    }

    /// @dev Helper to create a basic HybridOrder
    function createBasicHybridOrder(
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 deadline,
        uint256 auctionStartBlock
    ) internal view returns (HybridOrder memory) {
        HybridOutput[] memory outputs = new HybridOutput[](1);
        outputs[0] = HybridOutput({token: address(tokenOut), minAmount: outputAmount, recipient: swapper});

        return HybridOrder({
            info: OrderInfoBuilderV2.init(address(reactor)).withSwapper(swapper).withDeadline(deadline).withPreExecutionHook(
                tokenTransferHook
            ),
            cosigner: address(0),
            input: HybridInput(tokenIn, inputAmount),
            outputs: outputs,
            auctionStartBlock: auctionStartBlock,
            baselinePriorityFee: 0,
            scalingFactor: 1e18, // Neutral scaling
            priceCurve: new uint256[](0),
            cosignerData: HybridCosignerData({auctionTargetBlock: 0, supplementalPriceCurve: new uint256[](0)}),
            cosignature: ""
        });
    }

    function test_basicNoAuctionFill() public {
        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;
        uint256 deadline = block.timestamp + 1000;

        HybridOrder memory order = createBasicHybridOrder(inputAmount, outputAmount, deadline, block.number);

        // Seed tokens
        tokenIn.mint(address(swapper), inputAmount);
        tokenOut.mint(address(fillContract), outputAmount);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        (SignedOrder memory signedOrder, bytes32 orderHash) = signAndEncodeOrder(order);

        // Execute
        vm.expectEmit(true, true, true, true, address(reactor));
        emit Fill(orderHash, address(fillContract), swapper, order.info.nonce);
        fillContract.execute(signedOrder);

        assertEq(tokenIn.balanceOf(address(fillContract)), inputAmount);
        assertEq(tokenOut.balanceOf(swapper), outputAmount);
    }

    function test_dutchAuction_exactOut() public {
        uint256 inputStartAmount = 0.9 ether;
        uint256 inputEndAmount = 1.1 ether;
        uint256 outputAmount = 1 ether;
        uint256 deadline = block.timestamp + 1000;
        uint256 auctionStartBlock = block.number;

        // Create Dutch curve: decays to 80% over 100 blocks
        // Pack as (duration << 240) | scalingFactor
        uint256[] memory dutchCurve = new uint256[](1);
        dutchCurve[0] = (uint256(100) << 240) | uint256(0.8e18);

        HybridOutput[] memory outputs = new HybridOutput[](1);
        outputs[0] = HybridOutput({token: address(tokenOut), minAmount: outputAmount, recipient: swapper});

        HybridOrder memory order = HybridOrder({
            info: OrderInfoBuilderV2.init(address(reactor)).withSwapper(swapper).withDeadline(deadline).withPreExecutionHook(
                tokenTransferHook
            ),
            cosigner: address(0),
            input: HybridInput(tokenIn, inputEndAmount),
            outputs: outputs,
            auctionStartBlock: auctionStartBlock,
            baselinePriorityFee: 0,
            scalingFactor: 0.9e18, // Exact-out mode (< 1e18)
            priceCurve: dutchCurve,
            cosignerData: HybridCosignerData({auctionTargetBlock: 0, supplementalPriceCurve: new uint256[](0)}),
            cosignature: ""
        });

        // Seed tokens - need max amount for Permit2
        tokenIn.mint(address(swapper), inputEndAmount);
        tokenOut.mint(address(fillContract), outputAmount);
        tokenIn.forceApprove(swapper, address(permit2), inputEndAmount);

        // Fast forward 50 blocks - scaling goes from 0.9 to interpolated value
        // At 50 blocks (halfway), currentScalingFactor = 0.8 - (0.8 * 50/100) = 0.4
        // Input scaling = 0.4 (no priority adjustment)
        // Input amount interpolates: 0.9 + (1.1 - 0.9) * (0.9 - 0.4) / 0.9 = 0.9 + 0.2 * 0.556 = 1.011 ether
        vm.roll(block.number + 50);

        (SignedOrder memory signedOrder,) = signAndEncodeOrder(order);
        fillContract.execute(signedOrder);

        // Calculate expected input based on interpolation
        // scaling went from 0.9 to 0.4, so (0.9 - 0.4) / 0.9 = 55.6% of the way
        uint256 expectedInput = inputStartAmount + ((inputEndAmount - inputStartAmount) * 556 / 1000);
        assertApproxEqAbs(tokenIn.balanceOf(address(fillContract)), expectedInput, 0.01 ether);
        assertEq(tokenOut.balanceOf(swapper), outputAmount); // Fixed output
    }

    function test_exactInMode() public {
        uint256 inputAmount = 1 ether; // Fixed input
        uint256 outputStartAmount = 1.1 ether; // Start high (best for user)
        uint256 outputEndAmount = 1 ether; // End at minimum user accepts
        uint256 deadline = block.timestamp + 1000;

        HybridOutput[] memory outputs = new HybridOutput[](1);
        outputs[0] = HybridOutput({
            token: address(tokenOut),
            minAmount: outputEndAmount, // Minimum acceptable for exact-in
            recipient: swapper
        });

        HybridOrder memory order = HybridOrder({
            info: OrderInfoBuilderV2.init(address(reactor)).withSwapper(swapper).withDeadline(deadline).withPreExecutionHook(
                tokenTransferHook
            ),
            cosigner: address(0),
            input: HybridInput(tokenIn, inputAmount), // Both same for exact-in
            outputs: outputs,
            auctionStartBlock: 0, // No time decay for this test
            baselinePriorityFee: 0,
            scalingFactor: 1.1e18, // Exact-in mode (>= 1e18)
            priceCurve: new uint256[](0),
            cosignerData: HybridCosignerData({auctionTargetBlock: 0, supplementalPriceCurve: new uint256[](0)}),
            cosignature: ""
        });

        // Seed tokens
        tokenIn.mint(address(swapper), inputAmount);
        tokenOut.mint(address(fillContract), outputStartAmount); // Need enough for start amount
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        (SignedOrder memory signedOrder,) = signAndEncodeOrder(order);
        fillContract.execute(signedOrder);

        // With exact-in mode, no auction (auctionStartBlock=0), scalingFactor = 1.1e18
        // Output will be scaled up from minAmount by the scalingFactor
        // Output = minAmount * scalingFactor = 1 ether * 1.1 = 1.1 ether
        assertEq(tokenIn.balanceOf(address(fillContract)), inputAmount); // Fixed input
        assertEq(tokenOut.balanceOf(swapper), outputStartAmount); // minAmount * 1.1 = 1.1 ether
    }

    function test_deadlineEnforcement() public {
        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;
        uint256 deadline = block.timestamp + 100;

        HybridOrder memory order = createBasicHybridOrder(inputAmount, outputAmount, deadline, 0);

        // Seed tokens
        tokenIn.mint(address(swapper), inputAmount);
        tokenOut.mint(address(fillContract), outputAmount);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        // Fast forward past deadline
        vm.warp(deadline + 1);

        (SignedOrder memory signedOrder,) = signAndEncodeOrder(order);

        vm.expectRevert();
        fillContract.execute(signedOrder);
    }

    function test_invalidAuctionBlock() public {
        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;
        uint256 deadline = block.timestamp + 1000;
        uint256 auctionStartBlock = block.number + 100; // Future block

        HybridOrder memory order = createBasicHybridOrder(inputAmount, outputAmount, deadline, auctionStartBlock);

        // Seed tokens
        tokenIn.mint(address(swapper), inputAmount);
        tokenOut.mint(address(fillContract), outputAmount);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        (SignedOrder memory signedOrder,) = signAndEncodeOrder(order);

        vm.expectRevert(HybridAuctionResolver.InvalidAuctionBlock.selector);
        fillContract.execute(signedOrder);
    }

    function test_multiplePriceCurveElements_exactOut() public {
        uint256 inputStartAmount = 0.8 ether; // Start low
        uint256 inputEndAmount = 1.2 ether; // End high (max user pays)
        uint256 outputAmount = 1 ether; // Fixed output
        uint256 deadline = block.timestamp + 1000;
        uint256 auctionStartBlock = block.number;

        // Create multi-segment curve for exact-out mode (< 1e18 values):
        // Segments define how the scaling factor decays over time
        uint256[] memory priceCurve = new uint256[](2);
        priceCurve[0] = (uint256(50) << 240) | uint256(0.8e18); // First 50 blocks
        priceCurve[1] = (uint256(50) << 240) | uint256(0.6e18); // Next 50 blocks

        HybridOutput[] memory outputs = new HybridOutput[](1);
        outputs[0] = HybridOutput({token: address(tokenOut), minAmount: outputAmount, recipient: swapper});

        // Seed tokens for multiple executions
        tokenIn.mint(address(swapper), inputEndAmount * 3);
        tokenOut.mint(address(fillContract), outputAmount * 2);
        tokenIn.forceApprove(swapper, address(permit2), inputEndAmount * 3);

        // Test at 25 blocks (halfway through first segment)
        // PriceCurve interpolates from 0.8 toward 0.6
        vm.roll(block.number + 25);
        HybridOrder memory order1 = HybridOrder({
            info: OrderInfoBuilderV2.init(address(reactor)).withSwapper(swapper).withDeadline(deadline).withPreExecutionHook(
                tokenTransferHook
            ).withNonce(1),
            cosigner: address(0),
            input: HybridInput(tokenIn, inputEndAmount),
            outputs: outputs,
            auctionStartBlock: auctionStartBlock,
            baselinePriorityFee: 0,
            scalingFactor: 0.9e18, // Exact-out mode
            priceCurve: priceCurve,
            cosignerData: HybridCosignerData({auctionTargetBlock: 0, supplementalPriceCurve: new uint256[](0)}),
            cosignature: ""
        });

        (SignedOrder memory signedOrder,) = signAndEncodeOrder(order1);
        fillContract.execute(signedOrder);

        // Verify first execution
        uint256 firstBalance = tokenIn.balanceOf(address(fillContract));
        assertGt(firstBalance, 0);
        assertEq(tokenOut.balanceOf(swapper), outputAmount);

        // Test at 75 blocks (halfway through second segment)
        vm.roll(auctionStartBlock + 75);
        HybridOrder memory order2 = HybridOrder({
            info: OrderInfoBuilderV2.init(address(reactor)).withSwapper(swapper).withDeadline(deadline).withPreExecutionHook(
                tokenTransferHook
            ).withNonce(2),
            cosigner: address(0),
            input: HybridInput(tokenIn, inputEndAmount),
            outputs: outputs,
            auctionStartBlock: auctionStartBlock,
            baselinePriorityFee: 0,
            scalingFactor: 0.9e18,
            priceCurve: priceCurve,
            cosignerData: HybridCosignerData({auctionTargetBlock: 0, supplementalPriceCurve: new uint256[](0)}),
            cosignature: ""
        });

        (signedOrder,) = signAndEncodeOrder(order2);
        fillContract.execute(signedOrder);

        // Verify both executions completed
        assertGt(tokenIn.balanceOf(address(fillContract)), firstBalance);
        assertEq(tokenOut.balanceOf(swapper), outputAmount * 2);
    }

    function test_multiplePriceCurveElements_exactIn() public {
        uint256 inputAmount = 1 ether; // Fixed input
        uint256 outputStartAmount = 1.2 ether; // Start high
        uint256 outputEndAmount = 1 ether; // End at minimum
        uint256 deadline = block.timestamp + 1000;
        uint256 auctionStartBlock = block.number;

        // Create multi-segment curve for exact-in mode (>= 1e18 values):
        // Segments define how outputs decay from high to low
        // Both values must be >= 1e18 to avoid crossing threshold
        uint256[] memory priceCurve = new uint256[](1);
        priceCurve[0] = (uint256(100) << 240) | uint256(1.15e18); // Single segment

        HybridOutput[] memory outputs = new HybridOutput[](1);
        outputs[0] = HybridOutput({token: address(tokenOut), minAmount: outputEndAmount, recipient: swapper});

        // Seed tokens - need extra output for scaling
        tokenIn.mint(address(swapper), inputAmount * 2);
        tokenOut.mint(address(fillContract), outputStartAmount * 3);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount * 2);

        // Test at 20 blocks (halfway through first segment)
        vm.roll(block.number + 20);
        HybridOrder memory order1 = HybridOrder({
            info: OrderInfoBuilderV2.init(address(reactor)).withSwapper(swapper).withDeadline(deadline).withPreExecutionHook(
                tokenTransferHook
            ).withNonce(1),
            cosigner: address(0),
            input: HybridInput(tokenIn, inputAmount), // Fixed for exact-in
            outputs: outputs,
            auctionStartBlock: auctionStartBlock,
            baselinePriorityFee: 0,
            scalingFactor: 1.2e18, // Exact-in mode
            priceCurve: priceCurve,
            cosignerData: HybridCosignerData({auctionTargetBlock: 0, supplementalPriceCurve: new uint256[](0)}),
            cosignature: ""
        });

        (SignedOrder memory signedOrder,) = signAndEncodeOrder(order1);
        fillContract.execute(signedOrder);

        // Verify first execution
        assertEq(tokenIn.balanceOf(address(fillContract)), inputAmount); // Fixed input
        uint256 firstOutput = tokenOut.balanceOf(swapper);
        assertGt(firstOutput, outputEndAmount); // More than minimum

        // Test at 70 blocks (30 blocks into second segment)
        vm.roll(auctionStartBlock + 70);
        HybridOrder memory order2 = HybridOrder({
            info: OrderInfoBuilderV2.init(address(reactor)).withSwapper(swapper).withDeadline(deadline).withPreExecutionHook(
                tokenTransferHook
            ).withNonce(2),
            cosigner: address(0),
            input: HybridInput(tokenIn, inputAmount),
            outputs: outputs,
            auctionStartBlock: auctionStartBlock,
            baselinePriorityFee: 0,
            scalingFactor: 1.2e18,
            priceCurve: priceCurve,
            cosignerData: HybridCosignerData({auctionTargetBlock: 0, supplementalPriceCurve: new uint256[](0)}),
            cosignature: ""
        });

        (signedOrder,) = signAndEncodeOrder(order2);
        fillContract.execute(signedOrder);

        // Verify both executions
        assertEq(tokenIn.balanceOf(address(fillContract)), inputAmount * 2); // 2x fixed input
        assertGt(tokenOut.balanceOf(swapper), firstOutput); // Got more output total
    }

    function test_zeroDurationPriceCurve_exactOut() public {
        uint256 inputStartAmount = 0.8 ether;
        uint256 inputEndAmount = 1.2 ether;
        uint256 outputAmount = 1 ether;
        uint256 deadline = block.timestamp + 1000;
        uint256 auctionStartBlock = block.number;

        // Create curve with zero-duration element (instant jump):
        uint256[] memory priceCurve = new uint256[](3);
        priceCurve[0] = (uint256(30) << 240) | uint256(0.9e18);
        priceCurve[1] = (uint256(0) << 240) | uint256(0.7e18); // Zero duration - instant jump
        priceCurve[2] = (uint256(40) << 240) | uint256(0.5e18);

        HybridOutput[] memory outputs = new HybridOutput[](1);
        outputs[0] = HybridOutput({token: address(tokenOut), minAmount: outputAmount, recipient: swapper});

        // Seed tokens
        tokenIn.mint(address(swapper), inputEndAmount * 2);
        tokenOut.mint(address(fillContract), outputAmount * 2);
        tokenIn.forceApprove(swapper, address(permit2), inputEndAmount * 2);

        // Test at exactly 30 blocks (should be at the instant jump point)
        vm.roll(block.number + 30);
        HybridOrder memory order1 = HybridOrder({
            info: OrderInfoBuilderV2.init(address(reactor)).withSwapper(swapper).withDeadline(deadline).withPreExecutionHook(
                tokenTransferHook
            ).withNonce(1),
            cosigner: address(0),
            input: HybridInput(tokenIn, inputEndAmount),
            outputs: outputs,
            auctionStartBlock: auctionStartBlock,
            baselinePriorityFee: 0,
            scalingFactor: 0.85e18, // Exact-out mode
            priceCurve: priceCurve,
            cosignerData: HybridCosignerData({auctionTargetBlock: 0, supplementalPriceCurve: new uint256[](0)}),
            cosignature: ""
        });

        (SignedOrder memory signedOrder,) = signAndEncodeOrder(order1);
        fillContract.execute(signedOrder);

        uint256 firstInput = tokenIn.balanceOf(address(fillContract));
        assertGt(firstInput, 0);
        assertEq(tokenOut.balanceOf(swapper), outputAmount);

        // Test at 50 blocks (20 blocks into the segment after the jump)
        vm.roll(auctionStartBlock + 50);
        HybridOrder memory order2 = HybridOrder({
            info: OrderInfoBuilderV2.init(address(reactor)).withSwapper(swapper).withDeadline(deadline).withPreExecutionHook(
                tokenTransferHook
            ).withNonce(2),
            cosigner: address(0),
            input: HybridInput(tokenIn, inputEndAmount),
            outputs: outputs,
            auctionStartBlock: auctionStartBlock,
            baselinePriorityFee: 0,
            scalingFactor: 0.85e18,
            priceCurve: priceCurve,
            cosignerData: HybridCosignerData({auctionTargetBlock: 0, supplementalPriceCurve: new uint256[](0)}),
            cosignature: ""
        });

        (signedOrder,) = signAndEncodeOrder(order2);
        fillContract.execute(signedOrder);

        // Verify both executions
        assertGt(tokenIn.balanceOf(address(fillContract)), firstInput);
        assertEq(tokenOut.balanceOf(swapper), outputAmount * 2);
    }
}
