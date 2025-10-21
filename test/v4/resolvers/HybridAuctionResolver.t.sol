// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {DeployPermit2} from "../../util/DeployPermit2.sol";
import {PermitSignature} from "../../util/PermitSignature.sol";
import {OrderInfo} from "../../../src/v4/base/ReactorStructs.sol";
import {SignedOrder, InputToken, OutputToken} from "../../../src/base/ReactorStructs.sol";
import {ResolvedOrder} from "../../../src/v4/base/ReactorStructs.sol";
import {ReactorEvents} from "../../../src/base/ReactorEvents.sol";
import {Reactor} from "../../../src/v4/Reactor.sol";
import {HybridAuctionResolver} from "../../../src/v4/resolvers/HybridAuctionResolver.sol";
import {
    HybridOrder,
    HybridInput,
    HybridOutput,
    HybridCosignerData,
    HybridOrderLib
} from "../../../src/v4/lib/HybridOrderLib.sol";
import {CosignerLib} from "../../../src/lib/CosignerLib.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {MockERC20} from "../../util/mock/MockERC20.sol";
import {MockFillContract} from "../util/mock/MockFillContract.sol";
import {TokenTransferHook} from "../../../src/v4/hooks/TokenTransferHook.sol";
import {PriceCurveLib, PriceCurveElement} from "tribunal/src/lib/PriceCurveLib.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

/**
 * @title HybridAuctionResolverTest
 * @notice Comprehensive test suite for HybridAuctionResolver covering all PriceCurveLib edge cases
 * @dev Migrated from Tribunal's PriceCurveDocumentationTests, PriceCurveEdgeCasesTest, and MultipleZeroDurationTest
 */
contract HybridAuctionResolverTest is ReactorEvents, Test, PermitSignature, DeployPermit2 {
    using OrderInfoBuilder for OrderInfo;
    using HybridOrderLib for HybridOrder;
    using PriceCurveLib for uint256[];
    using FixedPointMathLib for uint256;

    uint256 constant ONE = 10 ** 18;
    uint256 constant COSIGNER_PRIVATE_KEY = 0x99999999;
    address internal constant PROTOCOL_FEE_OWNER = address(1);

    MockERC20 tokenIn;
    MockERC20 tokenOut;
    MockERC20 tokenOut2;
    MockFillContract fillContract;
    IPermit2 permit2;
    TokenTransferHook tokenTransferHook;
    Reactor reactor;
    HybridAuctionResolver resolver;
    uint256 swapperPrivateKey;
    address swapper;
    address cosigner;

    function setUp() public {
        tokenIn = new MockERC20("Input", "IN", 18);
        tokenOut = new MockERC20("Output", "OUT", 18);
        tokenOut2 = new MockERC20("Output2", "OUT2", 18);
        swapperPrivateKey = 0x12341234;
        swapper = vm.addr(swapperPrivateKey);
        cosigner = vm.addr(COSIGNER_PRIVATE_KEY);
        permit2 = IPermit2(deployPermit2());

        reactor = new Reactor(PROTOCOL_FEE_OWNER);
        resolver = new HybridAuctionResolver();
        tokenTransferHook = new TokenTransferHook(permit2, reactor);

        fillContract = new MockFillContract(address(reactor));

        // Provide tokens for tests
        tokenIn.mint(address(swapper), ONE * 1000);
        tokenOut.mint(address(fillContract), ONE * 1000);
        tokenOut2.mint(address(fillContract), ONE * 1000);

        // Provide ETH to fill contract for native transfers
        vm.deal(address(fillContract), type(uint256).max);
    }

    /// @dev Create and sign a HybridOrder
    function createAndSignOrder(HybridOrder memory order)
        internal
        view
        returns (SignedOrder memory signedOrder, bytes32 orderHash)
    {
        orderHash = order.hash();

        // Sign the order with swapper's key
        bytes memory sig = signOrder(swapperPrivateKey, address(permit2), order);

        // Encode the order data for the resolver
        bytes memory orderData = abi.encode(order);

        // Wrap with resolver address
        bytes memory encodedOrder = abi.encode(address(resolver), orderData);

        signedOrder = SignedOrder(encodedOrder, sig);
    }

    /// @dev Helper to cosign an order
    function cosignOrder(bytes32 orderHash, HybridCosignerData memory cosignerData)
        internal
        view
        returns (bytes memory cosignature)
    {
        bytes32 msgHash = keccak256(abi.encodePacked(orderHash, block.chainid, abi.encode(cosignerData)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(COSIGNER_PRIVATE_KEY, msgHash);
        cosignature = bytes.concat(r, s, bytes1(v));
    }

    /// @dev Helper to create a basic HybridOrder
    function createBasicOrder(
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 scalingFactor,
        uint256[] memory priceCurve,
        uint256 auctionStartBlock,
        uint256 nonce
    ) internal view returns (HybridOrder memory) {
        HybridOutput[] memory outputs = new HybridOutput[](1);
        outputs[0] = HybridOutput({token: address(tokenOut), minAmount: outputAmount, recipient: swapper});

        return HybridOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 1000)
                .withPreExecutionHook(tokenTransferHook).withAuctionResolver(resolver).withNonce(nonce),
            cosigner: address(0),
            input: HybridInput(tokenIn, inputAmount),
            outputs: outputs,
            auctionStartBlock: auctionStartBlock,
            baselinePriorityFee: 0,
            scalingFactor: scalingFactor,
            priceCurve: priceCurve,
            cosignerData: HybridCosignerData({auctionTargetBlock: 0, supplementalPriceCurve: new uint256[](0)}),
            cosignature: ""
        });
    }

    // ============================================================================
    // Basic Functionality Tests
    // ============================================================================

    function test_basicNoAuctionFill() public {
        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;

        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        HybridOrder memory order = createBasicOrder(inputAmount, outputAmount, 1e18, new uint256[](0), block.number, 0);

        (SignedOrder memory signedOrder, bytes32 orderHash) = createAndSignOrder(order);

        vm.expectEmit(true, true, true, true, address(reactor));
        emit Fill(orderHash, address(fillContract), swapper, order.info.nonce);
        fillContract.execute(signedOrder);

        assertEq(tokenIn.balanceOf(address(fillContract)), inputAmount);
        assertEq(tokenOut.balanceOf(swapper), outputAmount);
    }

    // ============================================================================
    // Documentation Test Cases (from PriceCurveDocumentationTests.t.sol)
    // ============================================================================

    function test_Doc_LinearDecay_DutchAuction() public {
        uint256[] memory priceCurve = new uint256[](1);
        priceCurve[0] = (100 << 240) | uint256(0.8e18); // 100 blocks from 0.8x to 1x

        uint256 inputMaxAmount = 1 ether;
        uint256 outputAmount = 1 ether;
        uint256 auctionStartBlock = block.number;

        tokenIn.forceApprove(swapper, address(permit2), inputMaxAmount * 2);

        // At start (block 0): 0.8x scaling
        HybridOrder memory order1 =
            createBasicOrder(inputMaxAmount, outputAmount, 0.9e18, priceCurve, auctionStartBlock, 1);
        (SignedOrder memory signedOrder1,) = createAndSignOrder(order1);
        fillContract.execute(signedOrder1);

        uint256 expectedScaling0 = 0.8e18;
        assertEq(tokenIn.balanceOf(address(fillContract)), inputMaxAmount.mulWad(expectedScaling0));

        // At block 50: 0.9x scaling (midpoint)
        vm.roll(auctionStartBlock + 50);
        HybridOrder memory order2 =
            createBasicOrder(inputMaxAmount, outputAmount, 0.9e18, priceCurve, auctionStartBlock, 2);
        (SignedOrder memory signedOrder2,) = createAndSignOrder(order2);
        fillContract.execute(signedOrder2);

        uint256 expectedScaling50 = 0.9e18;
        assertEq(
            tokenIn.balanceOf(address(fillContract)),
            inputMaxAmount.mulWad(expectedScaling0) + inputMaxAmount.mulWad(expectedScaling50)
        );
    }

    function test_Doc_StepFunctionWithPlateaus() public {
        uint256[] memory priceCurve = new uint256[](4);
        priceCurve[0] = (50 << 240) | uint256(1.5e18); // High price for 50 blocks
        priceCurve[1] = (0 << 240) | uint256(1.2e18); // Drop to 1.2x (zero-duration)
        priceCurve[2] = (50 << 240) | uint256(1.2e18); // Hold at 1.2x for 50 blocks (plateau)
        priceCurve[3] = (50 << 240) | uint256(1e18); // Final decay to 1.0x

        uint256 inputAmount = 1 ether;
        uint256 outputMinAmount = 1 ether;
        uint256 auctionStartBlock = block.number;

        tokenIn.forceApprove(swapper, address(permit2), inputAmount * 5);

        // At block 25: interpolating from 1.5x to 1.2x
        vm.roll(auctionStartBlock + 25);
        _executeOrder(inputAmount, outputMinAmount, 1.3e18, priceCurve, auctionStartBlock, 1);

        // Expected: 1.5 - (1.5 - 1.2) * (25/50) = 1.35
        uint256 balance1 = tokenOut.balanceOf(swapper);
        assertEq(balance1, outputMinAmount.mulWadUp(1.35e18));

        // At block 50: exactly at zero-duration element
        vm.roll(auctionStartBlock + 50);
        _executeOrder(inputAmount, outputMinAmount, 1.3e18, priceCurve, auctionStartBlock, 2);

        uint256 balance2 = tokenOut.balanceOf(swapper);
        assertEq(balance2, balance1 + outputMinAmount.mulWadUp(1.2e18));

        // At block 75: on plateau
        vm.roll(auctionStartBlock + 75);
        _executeOrder(inputAmount, outputMinAmount, 1.3e18, priceCurve, auctionStartBlock, 3);

        uint256 balance3 = tokenOut.balanceOf(swapper);
        assertEq(balance3, balance2 + outputMinAmount.mulWadUp(1.2e18));
    }

    /// @dev Helper to execute an order
    function _executeOrder(
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 scalingFactor,
        uint256[] memory priceCurve,
        uint256 auctionStartBlock,
        uint256 nonce
    ) internal {
        HybridOrder memory order =
            createBasicOrder(inputAmount, outputAmount, scalingFactor, priceCurve, auctionStartBlock, nonce);
        (SignedOrder memory signedOrder,) = createAndSignOrder(order);
        fillContract.execute(signedOrder);
    }

    function test_Doc_AggressiveInitialDiscount() public {
        uint256[] memory priceCurve = new uint256[](2);
        priceCurve[0] = (10 << 240) | uint256(5e17); // Start at 0.5x for 10 blocks
        priceCurve[1] = (90 << 240) | uint256(9e17); // Then 0.9x for 90 blocks

        uint256 inputMaxAmount = 1 ether;
        uint256 outputAmount = 1 ether;
        uint256 auctionStartBlock = block.number;

        tokenIn.forceApprove(swapper, address(permit2), inputMaxAmount * 3);

        // At block 0: 0.5x
        HybridOrder memory order1 =
            createBasicOrder(inputMaxAmount, outputAmount, 0.6e18, priceCurve, auctionStartBlock, 1);
        (SignedOrder memory signedOrder1,) = createAndSignOrder(order1);
        fillContract.execute(signedOrder1);

        assertEq(tokenIn.balanceOf(address(fillContract)), inputMaxAmount.mulWad(0.5e18));

        // At block 5: midway through first segment
        vm.roll(auctionStartBlock + 5);
        HybridOrder memory order2 =
            createBasicOrder(inputMaxAmount, outputAmount, 0.6e18, priceCurve, auctionStartBlock, 2);
        (SignedOrder memory signedOrder2,) = createAndSignOrder(order2);
        fillContract.execute(signedOrder2);

        // Expected: 0.5 + (0.9 - 0.5) * (5/10) = 0.7
        assertEq(
            tokenIn.balanceOf(address(fillContract)), inputMaxAmount.mulWad(0.5e18) + inputMaxAmount.mulWad(0.7e18)
        );
    }

    function test_Doc_AggressiveInitialDiscount_ExceedsDuration() public {
        uint256[] memory priceCurve = new uint256[](2);
        priceCurve[0] = (10 << 240) | uint256(5e17);
        priceCurve[1] = (90 << 240) | uint256(9e17);

        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;
        uint256 auctionStartBlock = block.number;

        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        // Try to execute at block 100 (exceeds curve duration of 0-99)
        vm.roll(auctionStartBlock + 100);

        HybridOrder memory order = createBasicOrder(inputAmount, outputAmount, 0.6e18, priceCurve, auctionStartBlock, 1);
        (SignedOrder memory signedOrder,) = createAndSignOrder(order);

        vm.expectRevert(PriceCurveLib.PriceCurveBlocksExceeded.selector);
        fillContract.execute(signedOrder);
    }

    function test_Doc_ReverseDutchAuction() public {
        uint256[] memory priceCurve = new uint256[](1);
        priceCurve[0] = (200 << 240) | uint256(2e18); // Start at 2x for 200 blocks

        uint256 inputAmount = 1 ether;
        uint256 outputMinAmount = 1 ether;
        uint256 auctionStartBlock = block.number;

        tokenIn.forceApprove(swapper, address(permit2), inputAmount * 3);

        // At block 0: 2x
        HybridOrder memory order1 =
            createBasicOrder(inputAmount, outputMinAmount, 1.5e18, priceCurve, auctionStartBlock, 1);
        (SignedOrder memory signedOrder1,) = createAndSignOrder(order1);
        fillContract.execute(signedOrder1);

        assertEq(tokenOut.balanceOf(swapper), outputMinAmount.mulWadUp(2e18));

        // At block 100: midway, should be 1.5x
        vm.roll(auctionStartBlock + 100);
        HybridOrder memory order2 =
            createBasicOrder(inputAmount, outputMinAmount, 1.5e18, priceCurve, auctionStartBlock, 2);
        (SignedOrder memory signedOrder2,) = createAndSignOrder(order2);
        fillContract.execute(signedOrder2);

        assertEq(tokenOut.balanceOf(swapper), outputMinAmount.mulWadUp(2e18) + outputMinAmount.mulWadUp(1.5e18));
    }

    function test_Doc_ReverseDutchAuction_ExceedsDuration() public {
        uint256[] memory priceCurve = new uint256[](1);
        priceCurve[0] = (200 << 240) | uint256(2e18);

        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;
        uint256 auctionStartBlock = block.number;

        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        // Try to execute at block 200 (exceeds curve duration of 0-199)
        vm.roll(auctionStartBlock + 200);

        HybridOrder memory order = createBasicOrder(inputAmount, outputAmount, 1.5e18, priceCurve, auctionStartBlock, 1);
        (SignedOrder memory signedOrder,) = createAndSignOrder(order);

        vm.expectRevert(PriceCurveLib.PriceCurveBlocksExceeded.selector);
        fillContract.execute(signedOrder);
    }

    function test_Doc_ComplexMultiPhaseCurve() public {
        uint256[] memory priceCurve = new uint256[](3);
        priceCurve[0] = (30 << 240) | uint256(0.5e18); // Start at 0.5x
        priceCurve[1] = (40 << 240) | uint256(0.7e18); // Rise to 0.7x at block 30
        priceCurve[2] = (30 << 240) | uint256(0.8e18); // Rise to 0.8x at block 70

        uint256 inputMaxAmount = 1 ether;
        uint256 outputAmount = 1 ether;
        uint256 auctionStartBlock = block.number;

        tokenIn.forceApprove(swapper, address(permit2), inputMaxAmount * 4);

        // Block 15: interpolating from 0.5 to 0.7
        vm.roll(auctionStartBlock + 15);
        HybridOrder memory order1 =
            createBasicOrder(inputMaxAmount, outputAmount, 0.75e18, priceCurve, auctionStartBlock, 1);
        (SignedOrder memory signedOrder1,) = createAndSignOrder(order1);
        fillContract.execute(signedOrder1);

        // Expected: 0.5 + (0.7 - 0.5) * (15/30) = 0.6
        assertEq(tokenIn.balanceOf(address(fillContract)), inputMaxAmount.mulWad(0.6e18));

        // Block 50: interpolating from 0.7 to 0.8
        vm.roll(auctionStartBlock + 50);
        HybridOrder memory order2 =
            createBasicOrder(inputMaxAmount, outputAmount, 0.75e18, priceCurve, auctionStartBlock, 2);
        (SignedOrder memory signedOrder2,) = createAndSignOrder(order2);
        fillContract.execute(signedOrder2);

        // Expected: 0.7 + (0.8 - 0.7) * (20/40) = 0.75
        assertEq(
            tokenIn.balanceOf(address(fillContract)), inputMaxAmount.mulWad(0.6e18) + inputMaxAmount.mulWad(0.75e18)
        );
    }

    // ============================================================================
    // Edge Cases (from PriceCurveEdgeCasesTest.t.sol)
    // ============================================================================

    function test_EmptyPriceCurve_ReturnsNeutralScaling() public {
        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;

        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        HybridOrder memory order = createBasicOrder(inputAmount, outputAmount, 1e18, new uint256[](0), 0, 0);

        (SignedOrder memory signedOrder,) = createAndSignOrder(order);
        fillContract.execute(signedOrder);

        // Neutral scaling: input and output unchanged
        assertEq(tokenIn.balanceOf(address(fillContract)), inputAmount);
        assertEq(tokenOut.balanceOf(swapper), outputAmount);
    }

    function test_ZeroDuration_InstantaneousPricePoint() public {
        uint256[] memory priceCurve = new uint256[](3);
        priceCurve[0] = (10 << 240) | uint256(1.2e18); // 10 blocks at 1.2x
        priceCurve[1] = (0 << 240) | uint256(1.5e18); // Zero duration at 1.5x
        priceCurve[2] = (20 << 240) | uint256(1e18); // 20 blocks ending at 1x

        uint256 inputAmount = 1 ether;
        uint256 outputMinAmount = 1 ether;
        uint256 auctionStartBlock = block.number;

        tokenIn.forceApprove(swapper, address(permit2), inputAmount * 3);

        // At block 5: interpolating from 1.2x towards 1.5x
        vm.roll(auctionStartBlock + 5);
        HybridOrder memory order1 =
            createBasicOrder(inputAmount, outputMinAmount, 1.3e18, priceCurve, auctionStartBlock, 1);
        (SignedOrder memory signedOrder1,) = createAndSignOrder(order1);
        fillContract.execute(signedOrder1);

        // Expected: 1.2 + (1.5 - 1.2) * (5/10) = 1.35
        assertApproxEqRel(tokenOut.balanceOf(swapper), outputMinAmount.mulWadUp(1.35e18), 0.01e18);

        // At block 10: exactly at zero-duration element
        vm.roll(auctionStartBlock + 10);
        HybridOrder memory order2 =
            createBasicOrder(inputAmount, outputMinAmount, 1.3e18, priceCurve, auctionStartBlock, 2);
        (SignedOrder memory signedOrder2,) = createAndSignOrder(order2);
        fillContract.execute(signedOrder2);

        assertApproxEqRel(
            tokenOut.balanceOf(swapper), outputMinAmount.mulWadUp(1.35e18) + outputMinAmount.mulWadUp(1.5e18), 0.01e18
        );
    }

    function test_ZeroScalingFactor_ExactOut() public {
        uint256[] memory priceCurve = new uint256[](1);
        priceCurve[0] = (10 << 240) | uint256(0); // Start at 0

        uint256 inputMaxAmount = 1 ether;
        uint256 outputAmount = 1 ether;
        uint256 auctionStartBlock = block.number;

        tokenIn.forceApprove(swapper, address(permit2), inputMaxAmount);

        // At targetBlock, scaling is 0
        HybridOrder memory order =
            createBasicOrder(inputMaxAmount, outputAmount, 0.5e18, priceCurve, auctionStartBlock, 1);
        (SignedOrder memory signedOrder,) = createAndSignOrder(order);
        fillContract.execute(signedOrder);

        // Input scaled to 0
        assertEq(tokenIn.balanceOf(address(fillContract)), 0);
        assertEq(tokenOut.balanceOf(swapper), outputAmount);
    }

    function test_RevertsExceedingTotalBlockDuration() public {
        uint256[] memory priceCurve = new uint256[](1);
        priceCurve[0] = (10 << 240) | uint256(1.2e18); // 10 blocks only

        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;
        uint256 auctionStartBlock = block.number;

        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        // Try to execute at block 10 (exceeds curve duration of 0-9)
        vm.roll(auctionStartBlock + 10);

        HybridOrder memory order = createBasicOrder(inputAmount, outputAmount, 1e18, priceCurve, auctionStartBlock, 1);
        (SignedOrder memory signedOrder,) = createAndSignOrder(order);

        vm.expectRevert(PriceCurveLib.PriceCurveBlocksExceeded.selector);
        fillContract.execute(signedOrder);
    }

    function test_RevertsInconsistentScalingDirections() public {
        uint256[] memory priceCurve = new uint256[](2);
        priceCurve[0] = (10 << 240) | uint256(1.5e18); // Increase (>1e18)
        priceCurve[1] = (10 << 240) | uint256(0.5e18); // Decrease (<1e18) - INVALID!

        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;
        uint256 auctionStartBlock = block.number;

        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        vm.roll(auctionStartBlock + 5);

        HybridOrder memory order = createBasicOrder(inputAmount, outputAmount, 1e18, priceCurve, auctionStartBlock, 1);
        (SignedOrder memory signedOrder,) = createAndSignOrder(order);

        vm.expectRevert(PriceCurveLib.InvalidPriceCurveParameters.selector);
        fillContract.execute(signedOrder);
    }

    function test_RevertsInvalidAuctionBlock() public {
        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;
        uint256 auctionStartBlock = block.number + 10; // Future block

        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        HybridOrder memory order =
            createBasicOrder(inputAmount, outputAmount, 1e18, new uint256[](0), auctionStartBlock, 1);
        (SignedOrder memory signedOrder,) = createAndSignOrder(order);

        vm.expectRevert(HybridAuctionResolver.InvalidAuctionBlock.selector);
        fillContract.execute(signedOrder);
    }

    function test_LinearDecay_DutchAuction_ExceedsDuration() public {
        uint256[] memory priceCurve = new uint256[](1);
        priceCurve[0] = (100 << 240) | uint256(0.8e18); // 100 blocks total duration

        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;
        uint256 auctionStartBlock = block.number;

        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        // At block 100: should revert (exceeds total duration)
        vm.roll(auctionStartBlock + 100);

        HybridOrder memory order = createBasicOrder(inputAmount, outputAmount, 0.9e18, priceCurve, auctionStartBlock, 1);
        (SignedOrder memory signedOrder,) = createAndSignOrder(order);

        vm.expectRevert(PriceCurveLib.PriceCurveBlocksExceeded.selector);
        fillContract.execute(signedOrder);
    }

    function test_StepFunctionWithPlateaus() public {
        uint256[] memory priceCurve = new uint256[](3);
        priceCurve[0] = (50 << 240) | uint256(1.5e18); // 50 blocks
        priceCurve[1] = (50 << 240) | uint256(1.2e18); // 50 blocks
        priceCurve[2] = (50 << 240) | uint256(1e18); // 50 blocks
        // Total duration: 150 blocks

        uint256 inputAmount = 1 ether;
        uint256 outputMinAmount = 1 ether;
        uint256 auctionStartBlock = block.number;

        tokenIn.forceApprove(swapper, address(permit2), inputAmount * 4);

        // During first segment (block 25)
        vm.roll(auctionStartBlock + 25);
        _executeOrder(inputAmount, outputMinAmount, 1.3e18, priceCurve, auctionStartBlock, 1);

        // Should interpolate from 1.5 towards 1.2
        // Expected: 1.5 - (1.5 - 1.2) * (25/50) = 1.35
        uint256 balance1 = tokenOut.balanceOf(swapper);
        assertEq(balance1, outputMinAmount.mulWadUp(1.35e18));

        // At block 50 (start of second segment)
        vm.roll(auctionStartBlock + 50);
        _executeOrder(inputAmount, outputMinAmount, 1.3e18, priceCurve, auctionStartBlock, 2);

        // Should interpolate from 1.2 towards 1.0
        // Expected: 1.2 - (1.2 - 1.0) * (0/50) = 1.2
        uint256 balance2 = tokenOut.balanceOf(swapper);
        assertEq(balance2, balance1 + outputMinAmount.mulWadUp(1.2e18));

        // At block 75 (halfway through second segment)
        vm.roll(auctionStartBlock + 75);
        _executeOrder(inputAmount, outputMinAmount, 1.3e18, priceCurve, auctionStartBlock, 3);

        // Block 75 is 25 blocks into segment 1 (blocks 50-100)
        // Expected: 1.2 - (1.2 - 1.0) * (25/50) = 1.1
        uint256 balance3 = tokenOut.balanceOf(swapper);
        assertEq(balance3, balance2 + outputMinAmount.mulWadUp(1.1e18));

        // At block 100 (start of third segment)
        vm.roll(auctionStartBlock + 100);
        _executeOrder(inputAmount, outputMinAmount, 1.3e18, priceCurve, auctionStartBlock, 4);

        // Expected: 1.0 - (1.0 - 1.0) * (0/50) = 1.0
        uint256 balance4 = tokenOut.balanceOf(swapper);
        assertEq(balance4, balance3 + outputMinAmount.mulWadUp(1e18));
    }

    function test_StepFunctionWithPlateaus_ExceedsDuration() public {
        uint256[] memory priceCurve = new uint256[](3);
        priceCurve[0] = (50 << 240) | uint256(1.5e18); // 50 blocks
        priceCurve[1] = (50 << 240) | uint256(1.2e18); // 50 blocks
        priceCurve[2] = (50 << 240) | uint256(1e18); // 50 blocks
        // Total duration: 150 blocks

        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;
        uint256 auctionStartBlock = block.number;

        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        // At block 150: should revert (exceeds total duration)
        vm.roll(auctionStartBlock + 150);

        HybridOrder memory order = createBasicOrder(inputAmount, outputAmount, 1.3e18, priceCurve, auctionStartBlock, 1);
        (SignedOrder memory signedOrder,) = createAndSignOrder(order);

        vm.expectRevert(PriceCurveLib.PriceCurveBlocksExceeded.selector);
        fillContract.execute(signedOrder);
    }

    function test_InvertedAuction_PriceIncreasesOverTime() public {
        uint256[] memory priceCurve = new uint256[](1);
        priceCurve[0] = (100 << 240) | uint256(0.5e18); // 100 blocks total duration

        uint256 inputMaxAmount = 1 ether;
        uint256 outputAmount = 1 ether;
        uint256 auctionStartBlock = block.number;

        tokenIn.forceApprove(swapper, address(permit2), inputMaxAmount * 3);

        // Price should increase from 0.5x to 1x over 100 blocks
        // At block 0: 0.5x
        HybridOrder memory order1 =
            createBasicOrder(inputMaxAmount, outputAmount, 0.6e18, priceCurve, auctionStartBlock, 1);
        (SignedOrder memory signedOrder1,) = createAndSignOrder(order1);
        fillContract.execute(signedOrder1);

        assertEq(tokenIn.balanceOf(address(fillContract)), inputMaxAmount.mulWad(0.5e18));

        // At block 50: midpoint, should be 0.75x
        vm.roll(auctionStartBlock + 50);
        HybridOrder memory order2 =
            createBasicOrder(inputMaxAmount, outputAmount, 0.6e18, priceCurve, auctionStartBlock, 2);
        (SignedOrder memory signedOrder2,) = createAndSignOrder(order2);
        fillContract.execute(signedOrder2);

        assertEq(
            tokenIn.balanceOf(address(fillContract)), inputMaxAmount.mulWad(0.5e18) + inputMaxAmount.mulWad(0.75e18)
        );

        // At block 99: close to 1.0x
        vm.roll(auctionStartBlock + 99);
        HybridOrder memory order3 =
            createBasicOrder(inputMaxAmount, outputAmount, 0.6e18, priceCurve, auctionStartBlock, 3);
        (SignedOrder memory signedOrder3,) = createAndSignOrder(order3);
        fillContract.execute(signedOrder3);

        assertApproxEqRel(
            tokenIn.balanceOf(address(fillContract)),
            inputMaxAmount.mulWad(0.5e18) + inputMaxAmount.mulWad(0.75e18) + inputMaxAmount.mulWad(0.995e18),
            0.001e18
        );
    }

    function test_ComplexMultiPhaseCurve() public {
        uint256[] memory priceCurve = new uint256[](3);
        priceCurve[0] = (30 << 240) | uint256(1.5e18); // 30 blocks
        priceCurve[1] = (40 << 240) | uint256(1.3e18); // 40 blocks
        priceCurve[2] = (30 << 240) | uint256(1.1e18); // 30 blocks
        // Total duration: 30 + 40 + 30 = 100 blocks

        uint256 inputAmount = 1 ether;
        uint256 outputMinAmount = 1 ether;
        uint256 auctionStartBlock = block.number;

        tokenIn.forceApprove(swapper, address(permit2), inputAmount * 4);

        // Block 15: interpolating from 1.5 to 1.3
        vm.roll(auctionStartBlock + 15);
        _executeOrder(inputAmount, outputMinAmount, 1.4e18, priceCurve, auctionStartBlock, 1);

        // Expected: 1.5 - (1.5 - 1.3) * (15/30) = 1.4
        uint256 balance1 = tokenOut.balanceOf(swapper);
        assertEq(balance1, outputMinAmount.mulWadUp(1.4e18));

        // Block 50: interpolating from 1.3 to 1.1
        vm.roll(auctionStartBlock + 50);
        _executeOrder(inputAmount, outputMinAmount, 1.4e18, priceCurve, auctionStartBlock, 2);

        // Expected: 1.3 - (1.3 - 1.1) * (20/40) = 1.2
        uint256 balance2 = tokenOut.balanceOf(swapper);
        assertEq(balance2, balance1 + outputMinAmount.mulWadUp(1.2e18));

        // Block 85: interpolating from 1.1 to 1.0
        vm.roll(auctionStartBlock + 85);
        _executeOrder(inputAmount, outputMinAmount, 1.4e18, priceCurve, auctionStartBlock, 3);

        // Expected: 1.1 - (1.1 - 1.0) * (15/30) = 1.05
        uint256 balance3 = tokenOut.balanceOf(swapper);
        assertEq(balance3, balance2 + outputMinAmount.mulWadUp(1.05e18));

        // Block 99: last valid block
        vm.roll(auctionStartBlock + 99);
        _executeOrder(inputAmount, outputMinAmount, 1.4e18, priceCurve, auctionStartBlock, 4);

        // Expected: 1.1 - (1.1 - 1.0) * (29/30) ≈ 1.0033
        uint256 balance4 = tokenOut.balanceOf(swapper);
        assertApproxEqRel(balance4, balance3 + outputMinAmount.mulWadUp(1.0033e18), 0.001e18);
    }

    // ============================================================================
    // Multiple Zero Duration Tests (from MultipleZeroDurationTest.t.sol)
    // ============================================================================

    function test_MultipleConsecutiveZeroDuration_DetailedBehavior() public {
        uint256[] memory priceCurve = new uint256[](4);
        priceCurve[0] = (10 << 240) | uint256(1.2e18); // 10 blocks at 1.2x
        priceCurve[1] = (0 << 240) | uint256(1.5e18); // First zero-duration at block 10
        priceCurve[2] = (0 << 240) | uint256(1.3e18); // Second zero-duration at block 10
        priceCurve[3] = (10 << 240) | uint256(1e18); // 10 blocks ending at 1x

        uint256 inputAmount = 1 ether;
        uint256 outputMinAmount = 1 ether;
        uint256 auctionStartBlock = block.number;

        tokenIn.forceApprove(swapper, address(permit2), inputAmount * 4);

        // At block 5: interpolating from 1.2x towards 1.5x
        vm.roll(auctionStartBlock + 5);
        HybridOrder memory order1 =
            createBasicOrder(inputAmount, outputMinAmount, 1.3e18, priceCurve, auctionStartBlock, 1);
        (SignedOrder memory signedOrder1,) = createAndSignOrder(order1);
        fillContract.execute(signedOrder1);

        // Expected: 1.2 + (1.5 - 1.2) * (5/10) = 1.35
        uint256 balance1 = tokenOut.balanceOf(swapper);
        assertEq(balance1, outputMinAmount.mulWadUp(1.35e18));

        // At block 10: returns FIRST zero-duration element (1.5x)
        vm.roll(auctionStartBlock + 10);
        HybridOrder memory order2 =
            createBasicOrder(inputAmount, outputMinAmount, 1.3e18, priceCurve, auctionStartBlock, 2);
        (SignedOrder memory signedOrder2,) = createAndSignOrder(order2);
        fillContract.execute(signedOrder2);

        uint256 balance2 = tokenOut.balanceOf(swapper);
        assertEq(balance2, balance1 + outputMinAmount.mulWadUp(1.5e18));

        // At block 11: interpolates from LAST zero-duration element (1.3x)
        vm.roll(auctionStartBlock + 11);
        HybridOrder memory order3 =
            createBasicOrder(inputAmount, outputMinAmount, 1.3e18, priceCurve, auctionStartBlock, 3);
        (SignedOrder memory signedOrder3,) = createAndSignOrder(order3);
        fillContract.execute(signedOrder3);

        // Expected: 1.3 - (1.3 - 1.0) * (1/10) = 1.27
        uint256 balance3 = tokenOut.balanceOf(swapper);
        assertEq(balance3, balance2 + outputMinAmount.mulWadUp(1.27e18));
    }

    function test_ThreeConsecutiveZeroDuration() public {
        uint256[] memory priceCurve = new uint256[](5);
        priceCurve[0] = (10 << 240) | uint256(1.1e18); // 10 blocks at 1.1x
        priceCurve[1] = (0 << 240) | uint256(1.6e18); // First zero-duration
        priceCurve[2] = (0 << 240) | uint256(1.4e18); // Second zero-duration
        priceCurve[3] = (0 << 240) | uint256(1.2e18); // Third zero-duration (last)
        priceCurve[4] = (10 << 240) | uint256(1e18); // 10 blocks to 1x

        uint256 inputAmount = 1 ether;
        uint256 outputMinAmount = 1 ether;
        uint256 auctionStartBlock = block.number;

        tokenIn.forceApprove(swapper, address(permit2), inputAmount * 3);

        // At block 10: returns FIRST zero-duration (1.6x)
        vm.roll(auctionStartBlock + 10);
        HybridOrder memory order1 =
            createBasicOrder(inputAmount, outputMinAmount, 1.3e18, priceCurve, auctionStartBlock, 1);
        (SignedOrder memory signedOrder1,) = createAndSignOrder(order1);
        fillContract.execute(signedOrder1);

        assertEq(tokenOut.balanceOf(swapper), outputMinAmount.mulWadUp(1.6e18));

        // At block 11: interpolates from LAST (third) zero-duration (1.2x)
        vm.roll(auctionStartBlock + 11);
        HybridOrder memory order2 =
            createBasicOrder(inputAmount, outputMinAmount, 1.3e18, priceCurve, auctionStartBlock, 2);
        (SignedOrder memory signedOrder2,) = createAndSignOrder(order2);
        fillContract.execute(signedOrder2);

        // Expected: 1.2 - (1.2 - 1.0) * (1/10) = 1.18
        assertEq(tokenOut.balanceOf(swapper), outputMinAmount.mulWadUp(1.6e18) + outputMinAmount.mulWadUp(1.18e18));
    }

    // ============================================================================
    // Priority Fee Tests
    // ============================================================================

    function test_PriorityFee_ExactIn_IncreasesWithGas() public {
        uint256[] memory priceCurve = new uint256[](1);
        priceCurve[0] = (100 << 240) | uint256(1.2e18);

        uint256 baselinePriorityFee = 10 gwei;
        uint256 scalingFactor = 1.00000000001e18; // Exact-in mode (very close to neutral)
        uint256 inputAmount = 1 ether;
        uint256 outputMinAmount = 1 ether;
        uint256 auctionStartBlock = block.number;

        // Set priority fee of 5 gwei above baseline
        vm.fee(1 gwei);
        vm.txGasPrice(1 gwei + baselinePriorityFee + 5 gwei);

        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        vm.roll(auctionStartBlock + 50); // Midway through curve

        HybridOutput[] memory outputs = new HybridOutput[](1);
        outputs[0] = HybridOutput({token: address(tokenOut), minAmount: outputMinAmount, recipient: swapper});

        HybridOrder memory order = HybridOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 1000)
                .withPreExecutionHook(tokenTransferHook).withAuctionResolver(resolver),
            cosigner: address(0),
            input: HybridInput(tokenIn, inputAmount),
            outputs: outputs,
            auctionStartBlock: auctionStartBlock,
            baselinePriorityFee: baselinePriorityFee,
            scalingFactor: scalingFactor,
            priceCurve: priceCurve,
            cosignerData: HybridCosignerData({auctionTargetBlock: 0, supplementalPriceCurve: new uint256[](0)}),
            cosignature: ""
        });

        (SignedOrder memory signedOrder,) = createAndSignOrder(order);
        fillContract.execute(signedOrder);

        // Current scaling from curve: 1.2 - (1.2-1.0) * 0.5 = 1.1
        // scalingFactor = 1.00000000001e18, priorityFee = 5 gwei
        // scalingMultiplier = 1.1e18 + ((1.00000000001e18 - 1e18) * 5 gwei)
        uint256 expectedScaling = 1.1e18 + ((scalingFactor - 1e18) * 5 gwei);

        assertApproxEqRel(tokenOut.balanceOf(swapper), outputMinAmount.mulWadUp(expectedScaling), 0.001e18);
    }

    function test_PriorityFee_ExactOut_DecreasesWithGas() public {
        uint256[] memory priceCurve = new uint256[](1);
        priceCurve[0] = (100 << 240) | uint256(0.8e18);

        uint256 baselinePriorityFee = 10 gwei;
        uint256 scalingFactor = 0.999e18; // Exact-out mode
        uint256 inputMaxAmount = 1 ether;
        uint256 outputAmount = 1 ether;
        uint256 auctionStartBlock = block.number;

        // Set smaller priority fee to avoid underflow
        vm.fee(1 gwei);
        vm.txGasPrice(1 gwei + baselinePriorityFee + 1 wei);

        tokenIn.forceApprove(swapper, address(permit2), inputMaxAmount);

        vm.roll(auctionStartBlock + 50); // Midway through curve

        HybridOutput[] memory outputs = new HybridOutput[](1);
        outputs[0] = HybridOutput({token: address(tokenOut), minAmount: outputAmount, recipient: swapper});

        HybridOrder memory order = HybridOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 1000)
                .withPreExecutionHook(tokenTransferHook).withAuctionResolver(resolver),
            cosigner: address(0),
            input: HybridInput(tokenIn, inputMaxAmount),
            outputs: outputs,
            auctionStartBlock: auctionStartBlock,
            baselinePriorityFee: baselinePriorityFee,
            scalingFactor: scalingFactor,
            priceCurve: priceCurve,
            cosignerData: HybridCosignerData({auctionTargetBlock: 0, supplementalPriceCurve: new uint256[](0)}),
            cosignature: ""
        });

        (SignedOrder memory signedOrder,) = createAndSignOrder(order);
        fillContract.execute(signedOrder);

        // Output fixed in exact-out
        assertEq(tokenOut.balanceOf(swapper), outputAmount);

        // Current scaling from curve: 0.8 + (1.0-0.8) * 0.5 = 0.9
        // Priority adjustment: 0.9 - (1.0 - 0.999) * 1 wei
        uint256 currentCurveScaling = 0.9e18;
        uint256 expectedScaling = currentCurveScaling - ((1e18 - scalingFactor) * 1);
        assertApproxEqRel(tokenIn.balanceOf(address(fillContract)), inputMaxAmount.mulWad(expectedScaling), 0.001e18);
    }

    // ============================================================================
    // DeriveAmounts Tests (from TribunalDeriveAmountsTest.t.sol)
    // ============================================================================

    function test_DeriveAmounts_NoPriorityFee() public {
        uint256 inputAmount = 100 ether;
        uint256 outputAmount = 95 ether;
        uint256 baselinePriorityFee = 100 gwei;
        uint256 scalingFactor = 1e18;

        vm.fee(baselinePriorityFee);
        vm.txGasPrice(baselinePriorityFee + 1 wei);

        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        HybridOrder memory order = createBasicOrder(inputAmount, outputAmount, scalingFactor, new uint256[](0), 0, 0);

        (SignedOrder memory signedOrder,) = createAndSignOrder(order);
        fillContract.execute(signedOrder);

        // Neutral scaling with no priority fee above baseline
        assertEq(tokenOut.balanceOf(swapper), outputAmount);
        assertEq(tokenIn.balanceOf(address(fillContract)), inputAmount);
    }

    function test_DeriveAmounts_ExactOut() public {
        uint256[] memory priceCurve = new uint256[](0);
        uint256 inputMaxAmount = 1 ether;
        uint256 outputAmount = 0.95 ether;
        uint256 baselinePriorityFee = 100 gwei;
        uint256 scalingFactor = 0.5e18;
        uint256 auctionStartBlock = block.number;

        vm.fee(1 gwei);
        vm.txGasPrice(1 gwei + baselinePriorityFee + 2 wei);

        tokenIn.forceApprove(swapper, address(permit2), inputMaxAmount);

        HybridOutput[] memory outputs = new HybridOutput[](1);
        outputs[0] = HybridOutput({token: address(tokenOut), minAmount: outputAmount, recipient: swapper});

        HybridOrder memory order = HybridOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 1000)
                .withPreExecutionHook(tokenTransferHook).withAuctionResolver(resolver),
            cosigner: address(0),
            input: HybridInput(tokenIn, inputMaxAmount),
            outputs: outputs,
            auctionStartBlock: auctionStartBlock,
            baselinePriorityFee: baselinePriorityFee,
            scalingFactor: scalingFactor,
            priceCurve: priceCurve,
            cosignerData: HybridCosignerData({auctionTargetBlock: 0, supplementalPriceCurve: new uint256[](0)}),
            cosignature: ""
        });

        (SignedOrder memory signedOrder,) = createAndSignOrder(order);
        fillContract.execute(signedOrder);

        // Output fixed in exact-out mode
        assertEq(tokenOut.balanceOf(swapper), outputAmount);

        // scalingMultiplier = 1e18 - ((1e18 - 0.5e18) * 2)
        uint256 scalingMultiplier = 1e18 - ((1e18 - scalingFactor) * 2);
        uint256 expectedInput = inputMaxAmount.mulWad(scalingMultiplier);
        assertEq(tokenIn.balanceOf(address(fillContract)), expectedInput);
    }

    function test_DeriveAmounts_ExactIn() public {
        uint256[] memory priceCurve = new uint256[](0);
        uint256 inputAmount = 1 ether;
        uint256 outputMinAmount = 0.95 ether;
        uint256 baselinePriorityFee = 100 gwei;
        uint256 scalingFactor = 1.5e18;
        uint256 auctionStartBlock = block.number;

        vm.fee(1 gwei);
        vm.txGasPrice(1 gwei + baselinePriorityFee + 2 wei);

        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        HybridOutput[] memory outputs = new HybridOutput[](1);
        outputs[0] = HybridOutput({token: address(tokenOut), minAmount: outputMinAmount, recipient: swapper});

        HybridOrder memory order = HybridOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 1000)
                .withPreExecutionHook(tokenTransferHook).withAuctionResolver(resolver),
            cosigner: address(0),
            input: HybridInput(tokenIn, inputAmount),
            outputs: outputs,
            auctionStartBlock: auctionStartBlock,
            baselinePriorityFee: baselinePriorityFee,
            scalingFactor: scalingFactor,
            priceCurve: priceCurve,
            cosignerData: HybridCosignerData({auctionTargetBlock: 0, supplementalPriceCurve: new uint256[](0)}),
            cosignature: ""
        });

        (SignedOrder memory signedOrder,) = createAndSignOrder(order);
        fillContract.execute(signedOrder);

        // Input unchanged in exact-in mode
        assertEq(tokenIn.balanceOf(address(fillContract)), inputAmount);

        // scalingMultiplier = 1e18 + ((1.5e18 - 1e18) * 2)
        uint256 scalingMultiplier = 1e18 + ((scalingFactor - 1e18) * 2);
        uint256 expectedOutput = outputMinAmount.mulWadUp(scalingMultiplier);
        assertEq(tokenOut.balanceOf(swapper), expectedOutput);
    }

    function test_DeriveAmounts_ExtremePriorityFee() public {
        uint256[] memory priceCurve = new uint256[](0);
        uint256 inputAmount = 1 ether;
        uint256 outputMinAmount = 0.95 ether;
        uint256 baselinePriorityFee = 100 gwei;
        uint256 scalingFactor = 1.5e18;
        uint256 auctionStartBlock = block.number;

        uint256 baseFee = 1 gwei;
        vm.fee(baseFee);
        vm.txGasPrice(baseFee + baselinePriorityFee + 10 wei);

        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        HybridOutput[] memory outputs = new HybridOutput[](1);
        outputs[0] = HybridOutput({token: address(tokenOut), minAmount: outputMinAmount, recipient: swapper});

        HybridOrder memory order = HybridOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 1000)
                .withPreExecutionHook(tokenTransferHook).withAuctionResolver(resolver),
            cosigner: address(0),
            input: HybridInput(tokenIn, inputAmount),
            outputs: outputs,
            auctionStartBlock: auctionStartBlock,
            baselinePriorityFee: baselinePriorityFee,
            scalingFactor: scalingFactor,
            priceCurve: priceCurve,
            cosignerData: HybridCosignerData({auctionTargetBlock: 0, supplementalPriceCurve: new uint256[](0)}),
            cosignature: ""
        });

        (SignedOrder memory signedOrder,) = createAndSignOrder(order);
        fillContract.execute(signedOrder);

        // Output unchanged in exact-in mode
        assertEq(tokenIn.balanceOf(address(fillContract)), inputAmount);

        // scalingMultiplier = 1e18 + ((1.5e18 - 1e18) * 10)
        uint256 scalingMultiplier = 1e18 + ((scalingFactor - 1e18) * 10);
        uint256 expectedOutput = outputMinAmount.mulWadUp(scalingMultiplier);
        assertEq(tokenOut.balanceOf(swapper), expectedOutput);
    }

    function test_DeriveAmounts_RealisticExactIn() public {
        uint256[] memory priceCurve = new uint256[](0);
        uint256 inputAmount = 1 ether;
        uint256 outputMinAmount = 0.95 ether;
        uint256 baselinePriorityFee = 100 gwei;
        uint256 scalingFactor = 1000000000100000000; // 1.0000000001e18
        uint256 auctionStartBlock = block.number;

        vm.fee(1 gwei);
        vm.txGasPrice(1 gwei + baselinePriorityFee + 5 gwei);

        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        HybridOutput[] memory outputs = new HybridOutput[](1);
        outputs[0] = HybridOutput({token: address(tokenOut), minAmount: outputMinAmount, recipient: swapper});

        HybridOrder memory order = HybridOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 1000)
                .withPreExecutionHook(tokenTransferHook).withAuctionResolver(resolver),
            cosigner: address(0),
            input: HybridInput(tokenIn, inputAmount),
            outputs: outputs,
            auctionStartBlock: auctionStartBlock,
            baselinePriorityFee: baselinePriorityFee,
            scalingFactor: scalingFactor,
            priceCurve: priceCurve,
            cosignerData: HybridCosignerData({auctionTargetBlock: 0, supplementalPriceCurve: new uint256[](0)}),
            cosignature: ""
        });

        (SignedOrder memory signedOrder,) = createAndSignOrder(order);
        fillContract.execute(signedOrder);

        // Output unchanged in exact-in mode
        assertEq(tokenIn.balanceOf(address(fillContract)), inputAmount);

        uint256 scalingMultiplier = 1e18 + ((scalingFactor - 1e18) * 5 gwei);
        uint256 expectedOutput = outputMinAmount.mulWadUp(scalingMultiplier);
        assertEq(tokenOut.balanceOf(swapper), expectedOutput);
    }

    function test_DeriveAmounts_RealisticExactOut() public {
        uint256[] memory priceCurve = new uint256[](0);
        uint256 inputMaxAmount = 1 ether;
        uint256 outputAmount = 0.95 ether;
        uint256 baselinePriorityFee = 100 gwei;
        uint256 scalingFactor = 999999999900000000; // 0.9999999999e18
        uint256 auctionStartBlock = block.number;

        vm.fee(1 gwei);
        vm.txGasPrice(1 gwei + baselinePriorityFee + 5 gwei);

        tokenIn.forceApprove(swapper, address(permit2), inputMaxAmount);

        HybridOutput[] memory outputs = new HybridOutput[](1);
        outputs[0] = HybridOutput({token: address(tokenOut), minAmount: outputAmount, recipient: swapper});

        HybridOrder memory order = HybridOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 1000)
                .withPreExecutionHook(tokenTransferHook).withAuctionResolver(resolver),
            cosigner: address(0),
            input: HybridInput(tokenIn, inputMaxAmount),
            outputs: outputs,
            auctionStartBlock: auctionStartBlock,
            baselinePriorityFee: baselinePriorityFee,
            scalingFactor: scalingFactor,
            priceCurve: priceCurve,
            cosignerData: HybridCosignerData({auctionTargetBlock: 0, supplementalPriceCurve: new uint256[](0)}),
            cosignature: ""
        });

        (SignedOrder memory signedOrder,) = createAndSignOrder(order);
        fillContract.execute(signedOrder);

        // Output fixed in exact-out mode
        assertEq(tokenOut.balanceOf(swapper), outputAmount);

        uint256 scalingMultiplier = 1e18 - ((1e18 - scalingFactor) * 5 gwei);
        uint256 expectedInput = inputMaxAmount.mulWad(scalingMultiplier);
        assertEq(tokenIn.balanceOf(address(fillContract)), expectedInput);
    }

    function test_DeriveAmounts_WithPriceCurve() public {
        uint256[] memory priceCurve = new uint256[](3);
        priceCurve[0] = (3 << 240) | uint256(0.8e18); // 0.8 * 10^18 (scaling down)
        priceCurve[1] = (10 << 240) | uint256(0.6e18); // 0.6 * 10^18 (scaling down more)
        priceCurve[2] = (10 << 240) | uint256(0); // 0 * 10^18 (scaling down to 0)

        uint256 inputMaxAmount = 1 ether;
        uint256 outputAmount = 0.95 ether;
        uint256 scalingFactor = 1e18;
        uint256 auctionStartBlock = block.number;

        tokenIn.forceApprove(swapper, address(permit2), inputMaxAmount);

        // Fill at block 5
        vm.roll(auctionStartBlock + 5);

        HybridOrder memory order =
            createBasicOrder(inputMaxAmount, outputAmount, scalingFactor, priceCurve, auctionStartBlock, 1);

        (SignedOrder memory signedOrder,) = createAndSignOrder(order);
        fillContract.execute(signedOrder);

        // Output fixed in exact-out mode
        assertEq(tokenOut.balanceOf(swapper), outputAmount);

        // Calculate expected scaling at block 5
        // We're 5 blocks in, with first segment ending at block 3
        // So we're 5-3=2 blocks into the second segment (which has 10 blocks duration)
        // Interpolating from 0.6 to 0 (last segment ends at 0)
        // scalingMultiplier = 0.6 - (0.6 * 2/10) = 0.6 * 0.8 = 0.48
        uint256 expectedScaling = 0.48e18;
        uint256 expectedInput = inputMaxAmount.mulWad(expectedScaling);
        assertEq(tokenIn.balanceOf(address(fillContract)), expectedInput);
    }

    function test_DeriveAmounts_WithPriceCurve_Dutch() public {
        uint256[] memory priceCurve = new uint256[](1);
        priceCurve[0] = (10 << 240) | uint256(1.2e18);

        uint256 inputAmount = 1 ether;
        uint256 outputMinAmount = 0.95 ether;
        uint256 scalingFactor = 1e18;
        uint256 auctionStartBlock = block.number;

        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        vm.roll(auctionStartBlock + 5);

        HybridOrder memory order =
            createBasicOrder(inputAmount, outputMinAmount, scalingFactor, priceCurve, auctionStartBlock, 1);

        (SignedOrder memory signedOrder,) = createAndSignOrder(order);
        fillContract.execute(signedOrder);

        // With exact-in mode and price curve scaling down
        // 5 blocks in, 10 blocks in segment
        // Interpolating from 1.2 to 1 (last segment ends at 1e18)
        // scalingMultiplier = 1.2 - (0.2 * 5/10) = 1.1
        uint256 expectedScaling = 1.1e18;
        assertEq(tokenOut.balanceOf(swapper), outputMinAmount.mulWadUp(expectedScaling));
        assertEq(tokenIn.balanceOf(address(fillContract)), inputAmount);
    }

    function test_DeriveAmounts_WithPriceCurve_Dutch_nonNeutralEndScalingFactor() public {
        uint256[] memory priceCurve = new uint256[](2);
        priceCurve[0] = (10 << 240) | uint256(1.2e18);
        priceCurve[1] = (0 << 240) | uint256(1.1e18);

        uint256 inputAmount = 1 ether;
        uint256 outputMinAmount = 0.95 ether;
        uint256 scalingFactor = 1e18;
        uint256 auctionStartBlock = block.number;

        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        vm.roll(auctionStartBlock + 5);

        HybridOrder memory order =
            createBasicOrder(inputAmount, outputMinAmount, scalingFactor, priceCurve, auctionStartBlock, 1);

        (SignedOrder memory signedOrder,) = createAndSignOrder(order);
        fillContract.execute(signedOrder);

        // With exact-in mode and price curve scaling down
        // 5 blocks in, 10 blocks in segment
        // Interpolating from 1.2 to 1.1 (zero-duration element)
        // scalingMultiplier = 1.2 - (0.1 * 5/10) = 1.15
        uint256 expectedScaling = 1.15e18;
        assertEq(tokenOut.balanceOf(swapper), outputMinAmount.mulWadUp(expectedScaling));
        assertEq(tokenIn.balanceOf(address(fillContract)), inputAmount);
    }

    function test_DeriveAmounts_WithPriceCurve_ReverseDutch() public {
        uint256[] memory priceCurve = new uint256[](2);
        priceCurve[0] = (10 << 240) | uint256(0.8e18);
        priceCurve[1] = (10 << 240) | uint256(1e18);

        uint256 inputMaxAmount = 1 ether;
        uint256 outputAmount = 0.95 ether;
        uint256 scalingFactor = 1e18;
        uint256 auctionStartBlock = block.number;

        tokenIn.forceApprove(swapper, address(permit2), inputMaxAmount * 2);

        // Test at block 5
        vm.roll(auctionStartBlock + 5);
        HybridOrder memory order1 =
            createBasicOrder(inputMaxAmount, outputAmount, scalingFactor, priceCurve, auctionStartBlock, 1);
        (SignedOrder memory signedOrder1,) = createAndSignOrder(order1);
        fillContract.execute(signedOrder1);

        // With exact-out mode and price curve scaling up
        assertEq(tokenOut.balanceOf(swapper), outputAmount); // Output stays the same

        // Calculate expected claim amount based on interpolation at block 5
        // We're 5 blocks in, with segment ending at block 10
        // Interpolating from 0.8 to 1
        // scalingMultiplier = 0.8 + (0.2 * 5/10) = 0.9
        uint256 expectedScaling = 0.9e18;
        uint256 expectedInput = inputMaxAmount.mulWad(expectedScaling);
        assertEq(tokenIn.balanceOf(address(fillContract)), expectedInput);
    }

    function test_DeriveAmounts_InvalidTargetBlockDesignation() public {
        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;

        uint256[] memory priceCurve = new uint256[](1);
        priceCurve[0] = 1e18;

        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        HybridOrder memory order = createBasicOrder(inputAmount, outputAmount, 1e18, priceCurve, 0, 1);
        (SignedOrder memory signedOrder,) = createAndSignOrder(order);

        vm.expectRevert(HybridOrderLib.InvalidTargetBlockDesignation.selector);
        fillContract.execute(signedOrder);
    }

    // ============================================================================
    // Cosigner Tests
    // ============================================================================

    function test_CosignerOverrideAuctionTargetBlock() public {
        uint256[] memory priceCurve = new uint256[](1);
        priceCurve[0] = (10 << 240) | uint256(1.2e18);

        uint256 inputAmount = 1 ether;
        uint256 outputMinAmount = 1 ether;
        uint256 originalAuctionStart = block.number + 10;
        uint256 cosignerOverrideBlock = block.number;

        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        HybridOutput[] memory outputs = new HybridOutput[](1);
        outputs[0] = HybridOutput({token: address(tokenOut), minAmount: outputMinAmount, recipient: swapper});

        HybridCosignerData memory cosignerData =
            HybridCosignerData({auctionTargetBlock: cosignerOverrideBlock, supplementalPriceCurve: new uint256[](0)});

        HybridOrder memory order = HybridOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 1000)
                .withPreExecutionHook(tokenTransferHook).withAuctionResolver(resolver),
            cosigner: cosigner,
            input: HybridInput(tokenIn, inputAmount),
            outputs: outputs,
            auctionStartBlock: originalAuctionStart,
            baselinePriorityFee: 0,
            scalingFactor: 1.3e18,
            priceCurve: priceCurve,
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);

        (SignedOrder memory signedOrder, bytes32 orderHash) = createAndSignOrder(order);

        // Should succeed because cosigner overrides to current block
        vm.expectEmit(true, true, true, true, address(reactor));
        emit Fill(orderHash, address(fillContract), swapper, order.info.nonce);
        fillContract.execute(signedOrder);
    }

    function test_CosignerSupplementalPriceCurve() public {
        uint256[] memory baseCurve = new uint256[](1);
        baseCurve[0] = (10 << 240) | uint256(1.2e18); // Base: 1.2x

        uint256[] memory supplementalCurve = new uint256[](1);
        supplementalCurve[0] = uint256(1.1e18); // Add 0.1x (combined: 1.3x)

        uint256 inputAmount = 1 ether;
        uint256 outputMinAmount = 1 ether;
        uint256 auctionStartBlock = block.number;

        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        HybridOutput[] memory outputs = new HybridOutput[](1);
        outputs[0] = HybridOutput({token: address(tokenOut), minAmount: outputMinAmount, recipient: swapper});

        HybridCosignerData memory cosignerData =
            HybridCosignerData({auctionTargetBlock: 0, supplementalPriceCurve: supplementalCurve});

        HybridOrder memory order = HybridOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 1000)
                .withPreExecutionHook(tokenTransferHook).withAuctionResolver(resolver),
            cosigner: cosigner,
            input: HybridInput(tokenIn, inputAmount),
            outputs: outputs,
            auctionStartBlock: auctionStartBlock,
            baselinePriorityFee: 0,
            scalingFactor: 1.2e18,
            priceCurve: baseCurve,
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);

        (SignedOrder memory signedOrder,) = createAndSignOrder(order);
        fillContract.execute(signedOrder);

        // Combined scaling: 1.2 + 1.1 - 1.0 = 1.3
        assertEq(tokenOut.balanceOf(swapper), outputMinAmount.mulWadUp(1.3e18));
    }

    function test_RevertsWrongCosigner() public {
        address wrongCosigner = makeAddr("wrongCosigner");

        HybridOutput[] memory outputs = new HybridOutput[](1);
        outputs[0] = HybridOutput({token: address(tokenOut), minAmount: 0, recipient: swapper});

        HybridCosignerData memory cosignerData =
            HybridCosignerData({auctionTargetBlock: block.number, supplementalPriceCurve: new uint256[](0)});

        HybridOrder memory order = HybridOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 1000)
                .withPreExecutionHook(tokenTransferHook).withAuctionResolver(resolver),
            cosigner: wrongCosigner,
            input: HybridInput(tokenIn, 0),
            outputs: outputs,
            auctionStartBlock: block.number,
            baselinePriorityFee: 0,
            scalingFactor: 1e18,
            priceCurve: new uint256[](0),
            cosignerData: cosignerData,
            cosignature: bytes("")
        });
        order.cosignature = cosignOrder(order.hash(), cosignerData);

        (SignedOrder memory signedOrder,) = createAndSignOrder(order);

        vm.expectRevert(CosignerLib.InvalidCosignature.selector);
        fillContract.execute(signedOrder);
    }

    // ============================================================================
    // Multiple Outputs Tests
    // ============================================================================

    function test_MultipleOutputs_ExactIn() public {
        uint256[] memory priceCurve = new uint256[](1);
        priceCurve[0] = (100 << 240) | uint256(1.2e18); // Start at 1.2x for 100 blocks

        uint256 inputAmount = 1 ether;
        uint256 output1MinAmount = 0.5 ether;
        uint256 output2MinAmount = 0.3 ether;
        uint256 scalingFactor = 1.2e18;
        uint256 auctionStartBlock = block.number;

        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        HybridOutput[] memory outputs = new HybridOutput[](2);
        outputs[0] = HybridOutput({token: address(tokenOut), minAmount: output1MinAmount, recipient: swapper});
        outputs[1] = HybridOutput({token: address(tokenOut2), minAmount: output2MinAmount, recipient: swapper});

        HybridOrder memory order = HybridOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 1000)
                .withPreExecutionHook(tokenTransferHook).withAuctionResolver(resolver),
            cosigner: address(0),
            input: HybridInput(tokenIn, inputAmount),
            outputs: outputs,
            auctionStartBlock: auctionStartBlock,
            baselinePriorityFee: 0,
            scalingFactor: scalingFactor,
            priceCurve: priceCurve,
            cosignerData: HybridCosignerData({auctionTargetBlock: 0, supplementalPriceCurve: new uint256[](0)}),
            cosignature: ""
        });

        (SignedOrder memory signedOrder,) = createAndSignOrder(order);
        fillContract.execute(signedOrder);

        // At block 0, price curve gives 1.2x scaling
        assertEq(tokenIn.balanceOf(address(fillContract)), inputAmount);
        assertEq(tokenOut.balanceOf(swapper), output1MinAmount.mulWadUp(1.2e18));
        assertEq(tokenOut2.balanceOf(swapper), output2MinAmount.mulWadUp(1.2e18));
    }
}
