// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {DeployPermit2} from "../../util/DeployPermit2.sol";
import {PermitSignature} from "../../util/PermitSignature.sol";
import {OrderInfo, ResolvedOrder} from "../../../src/v4/base/ReactorStructs.sol";
import {SignedOrder, InputToken, OutputToken} from "../../../src/base/ReactorStructs.sol";
import {Reactor} from "../../../src/v4/Reactor.sol";
import {HybridAuctionResolver} from "../../../src/v4/resolvers/HybridAuctionResolver.sol";
import {
    HybridOrder,
    HybridInput,
    HybridOutput,
    HybridCosignerData,
    HybridOrderLib
} from "../../../src/v4/lib/HybridOrderLib.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {MockERC20} from "../../util/mock/MockERC20.sol";
import {TokenTransferHook} from "../../../src/v4/hooks/TokenTransferHook.sol";
import {OrderQuoter} from "../../../src/v4/lens/OrderQuoter.sol";
import {IReactor} from "../../../src/v4/interfaces/IReactor.sol";
import {IPreExecutionHook, IPostExecutionHook} from "../../../src/v4/interfaces/IHook.sol";
import {IAuctionResolver} from "../../../src/v4/interfaces/IAuctionResolver.sol";

contract OrderQuoterTest is Test, PermitSignature, DeployPermit2 {
    using OrderInfoBuilder for OrderInfo;
    using HybridOrderLib for HybridOrder;

    uint256 constant ONE = 10 ** 18;
    uint256 constant NEUTRAL_SCALING_FACTOR = 1e18;
    address internal constant PROTOCOL_FEE_OWNER = address(1);

    MockERC20 tokenIn;
    MockERC20 tokenOut;
    IPermit2 permit2;
    TokenTransferHook tokenTransferHook;
    Reactor reactor;
    HybridAuctionResolver resolver;
    OrderQuoter quoter;
    uint256 swapperPrivateKey;
    address swapper;

    function setUp() public {
        tokenIn = new MockERC20("Input", "IN", 18);
        tokenOut = new MockERC20("Output", "OUT", 18);
        swapperPrivateKey = 0x12341234;
        swapper = vm.addr(swapperPrivateKey);
        permit2 = IPermit2(deployPermit2());

        reactor = new Reactor(PROTOCOL_FEE_OWNER, permit2);
        resolver = new HybridAuctionResolver();
        tokenTransferHook = new TokenTransferHook(permit2, reactor);
        quoter = new OrderQuoter();

        // Provide tokens for tests
        tokenIn.mint(address(swapper), ONE * 1000);

        // Approve permit2 for swapper
        vm.prank(swapper);
        tokenIn.approve(address(permit2), type(uint256).max);
    }

    /// @dev Create and sign a HybridOrder, returning the encoded order bytes and signature
    function createAndSignOrder(HybridOrder memory order)
        internal
        view
        returns (bytes memory encodedOrder, bytes memory sig)
    {
        // Sign the order with swapper's key
        sig = signOrder(swapperPrivateKey, address(permit2), order);

        // Encode the order data for the resolver
        bytes memory orderData = abi.encode(order);

        // Wrap with resolver address
        encodedOrder = abi.encode(address(resolver), orderData);
    }

    /// @dev Create a basic HybridOrder for testing
    function createBasicOrder(uint256 inputAmount, uint256 outputAmount, uint256 nonce)
        internal
        view
        returns (HybridOrder memory)
    {
        HybridOutput[] memory outputs = new HybridOutput[](1);
        outputs[0] = HybridOutput({token: address(tokenOut), minAmount: outputAmount, recipient: swapper});

        return HybridOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 1000)
                .withPreExecutionHook(tokenTransferHook).withAuctionResolver(resolver).withNonce(nonce),
            cosigner: address(0),
            input: HybridInput(tokenIn, inputAmount),
            outputs: outputs,
            auctionStartBlock: block.number,
            baselinePriorityFee: 0,
            scalingFactor: NEUTRAL_SCALING_FACTOR,
            priceCurve: new uint256[](0),
            cosignerData: HybridCosignerData({auctionTargetBlock: 0, supplementalPriceCurve: new uint256[](0)}),
            cosignature: ""
        });
    }

    // ============================================================================
    // Basic Quote Tests
    // ============================================================================

    function test_quoteHybridOrder() public {
        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 2 ether;

        HybridOrder memory order = createBasicOrder(inputAmount, outputAmount, 0);
        (bytes memory encodedOrder, bytes memory sig) = createAndSignOrder(order);

        ResolvedOrder memory quote = quoter.quote(IReactor(address(reactor)), encodedOrder, sig);

        // Verify the resolved order
        assertEq(address(quote.input.token), address(tokenIn));
        assertEq(quote.input.amount, inputAmount);
        assertEq(quote.input.maxAmount, inputAmount);
        assertEq(quote.outputs.length, 1);
        assertEq(quote.outputs[0].token, address(tokenOut));
        assertEq(quote.outputs[0].amount, outputAmount);
        assertEq(quote.outputs[0].recipient, swapper);
        assertEq(quote.info.swapper, swapper);
        assertEq(quote.auctionResolver, address(resolver));
    }

    function test_quoteHybridOrder_multipleOutputs() public {
        uint256 inputAmount = 1 ether;
        uint256 outputAmount1 = 1 ether;
        uint256 outputAmount2 = 0.5 ether;
        address recipient2 = makeAddr("recipient2");

        HybridOutput[] memory outputs = new HybridOutput[](2);
        outputs[0] = HybridOutput({token: address(tokenOut), minAmount: outputAmount1, recipient: swapper});
        outputs[1] = HybridOutput({token: address(tokenOut), minAmount: outputAmount2, recipient: recipient2});

        HybridOrder memory order = HybridOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 1000)
                .withPreExecutionHook(tokenTransferHook).withAuctionResolver(resolver).withNonce(0),
            cosigner: address(0),
            input: HybridInput(tokenIn, inputAmount),
            outputs: outputs,
            auctionStartBlock: block.number,
            baselinePriorityFee: 0,
            scalingFactor: NEUTRAL_SCALING_FACTOR,
            priceCurve: new uint256[](0),
            cosignerData: HybridCosignerData({auctionTargetBlock: 0, supplementalPriceCurve: new uint256[](0)}),
            cosignature: ""
        });

        (bytes memory encodedOrder, bytes memory sig) = createAndSignOrder(order);
        ResolvedOrder memory quote = quoter.quote(IReactor(address(reactor)), encodedOrder, sig);

        assertEq(quote.outputs.length, 2);
        assertEq(quote.outputs[0].amount, outputAmount1);
        assertEq(quote.outputs[0].recipient, swapper);
        assertEq(quote.outputs[1].amount, outputAmount2);
        assertEq(quote.outputs[1].recipient, recipient2);
    }

    // ============================================================================
    // getAuctionResolver Tests
    // ============================================================================

    function test_getAuctionResolver() public view {
        HybridOrder memory order = createBasicOrder(1 ether, 1 ether, 0);
        (bytes memory encodedOrder,) = createAndSignOrder(order);

        address extractedResolver = quoter.getAuctionResolver(encodedOrder);
        assertEq(extractedResolver, address(resolver));
    }

    function test_getAuctionResolver_differentResolver() public {
        HybridAuctionResolver otherResolver = new HybridAuctionResolver();

        HybridOutput[] memory outputs = new HybridOutput[](1);
        outputs[0] = HybridOutput({token: address(tokenOut), minAmount: 1 ether, recipient: swapper});

        HybridOrder memory order = HybridOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 1000)
                .withPreExecutionHook(tokenTransferHook).withAuctionResolver(otherResolver).withNonce(0),
            cosigner: address(0),
            input: HybridInput(tokenIn, 1 ether),
            outputs: outputs,
            auctionStartBlock: block.number,
            baselinePriorityFee: 0,
            scalingFactor: NEUTRAL_SCALING_FACTOR,
            priceCurve: new uint256[](0),
            cosignerData: HybridCosignerData({auctionTargetBlock: 0, supplementalPriceCurve: new uint256[](0)}),
            cosignature: ""
        });

        bytes memory orderData = abi.encode(order);
        bytes memory encodedOrder = abi.encode(address(otherResolver), orderData);

        address extractedResolver = quoter.getAuctionResolver(encodedOrder);
        assertEq(extractedResolver, address(otherResolver));
    }

    // ============================================================================
    // Error Handling Tests
    // ============================================================================

    function test_quote_expiredOrder() public {
        HybridOutput[] memory outputs = new HybridOutput[](1);
        outputs[0] = HybridOutput({token: address(tokenOut), minAmount: 1 ether, recipient: swapper});

        // Create order with deadline in the past
        HybridOrder memory order = HybridOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp - 1)
                .withPreExecutionHook(tokenTransferHook).withAuctionResolver(resolver).withNonce(0),
            cosigner: address(0),
            input: HybridInput(tokenIn, 1 ether),
            outputs: outputs,
            auctionStartBlock: block.number,
            baselinePriorityFee: 0,
            scalingFactor: NEUTRAL_SCALING_FACTOR,
            priceCurve: new uint256[](0),
            cosignerData: HybridCosignerData({auctionTargetBlock: 0, supplementalPriceCurve: new uint256[](0)}),
            cosignature: ""
        });

        (bytes memory encodedOrder, bytes memory sig) = createAndSignOrder(order);

        // Quote should revert with DeadlinePassed
        vm.expectRevert(IReactor.DeadlinePassed.selector);
        quoter.quote(IReactor(address(reactor)), encodedOrder, sig);
    }

    function test_quote_invalidReactor() public {
        // Deploy a different reactor
        Reactor otherReactor = new Reactor(PROTOCOL_FEE_OWNER, permit2);

        HybridOrder memory order = createBasicOrder(1 ether, 1 ether, 0);
        (bytes memory encodedOrder, bytes memory sig) = createAndSignOrder(order);

        // Quote using wrong reactor should revert
        vm.expectRevert(IReactor.InvalidReactor.selector);
        quoter.quote(IReactor(address(otherReactor)), encodedOrder, sig);
    }

    function test_quote_emptyAuctionResolver() public {
        // Create order with zero address resolver - encode manually
        bytes memory orderData = abi.encode(createBasicOrder(1 ether, 1 ether, 0));
        bytes memory encodedOrder = abi.encode(address(0), orderData);
        bytes memory sig = hex""; // Dummy sig, won't get that far

        vm.expectRevert(IReactor.EmptyAuctionResolver.selector);
        quoter.quote(IReactor(address(reactor)), encodedOrder, sig);
    }

    // ============================================================================
    // Callback Tests
    // ============================================================================

    function test_reactorCallback_tooManyOrders() public {
        ResolvedOrder[] memory orders = new ResolvedOrder[](2);

        vm.expectRevert(OrderQuoter.OrdersLengthIncorrect.selector);
        quoter.reactorCallback(orders, bytes(""));
    }

    function test_reactorCallback_zeroOrders() public {
        ResolvedOrder[] memory orders = new ResolvedOrder[](0);

        vm.expectRevert(OrderQuoter.OrdersLengthIncorrect.selector);
        quoter.reactorCallback(orders, bytes(""));
    }

    // ============================================================================
    // Witness Type String Tests
    // ============================================================================

    function test_quote_witnessTypeString() public {
        HybridOrder memory order = createBasicOrder(1 ether, 1 ether, 0);
        (bytes memory encodedOrder, bytes memory sig) = createAndSignOrder(order);

        ResolvedOrder memory quote = quoter.quote(IReactor(address(reactor)), encodedOrder, sig);

        // Check that witness type string is set correctly
        assertEq(quote.witnessTypeString, HybridOrderLib.PERMIT2_ORDER_TYPE);
    }

    // ============================================================================
    // Order Hash Tests
    // ============================================================================

    function test_quote_orderHash() public {
        HybridOrder memory order = createBasicOrder(1 ether, 1 ether, 0);
        bytes32 expectedHash = order.hash();

        (bytes memory encodedOrder, bytes memory sig) = createAndSignOrder(order);
        ResolvedOrder memory quote = quoter.quote(IReactor(address(reactor)), encodedOrder, sig);

        assertEq(quote.hash, expectedHash);
    }

    // ============================================================================
    // ETH Receive Tests
    // ============================================================================

    function test_receiveETH() public {
        // Quoter should be able to receive ETH
        (bool success,) = address(quoter).call{value: 1 ether}("");
        assertTrue(success);
        assertEq(address(quoter).balance, 1 ether);
    }
}
