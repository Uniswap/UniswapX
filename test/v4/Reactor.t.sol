// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";

import {DeployPermit2} from "../util/DeployPermit2.sol";
import {IReactor} from "../../src/v4/interfaces/IReactor.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {Reactor} from "../../src/v4/Reactor.sol";
import {ReactorEvents} from "../../src/base/ReactorEvents.sol";
import {SignedOrder, InputToken, OutputToken} from "../../src/base/ReactorStructs.sol";
import {OrderInfo, ResolvedOrder} from "../../src/v4/base/ReactorStructs.sol";
import {OrderInfoBuilder} from "../v4/util/OrderInfoBuilder.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {MockFillContract} from "../v4/util/mock/MockFillContract.sol";
import {MockFeeController} from "../v4/util/mock/MockFeeController.sol";
import {MockPreExecutionHook} from "../v4/util/mock/MockPreExecutionHook.sol";
import {MockPostExecutionHook} from "../v4/util/mock/MockPostExecutionHook.sol";
import {TokenTransferHook} from "../../src/v4/hooks/TokenTransferHook.sol";
import {MockAuctionResolver} from "./util/mock/MockAuctionResolver.sol";
import {MockOrder, MockOrderLib} from "./util/mock/MockOrderLib.sol";
import {ArrayBuilder} from "../util/ArrayBuilder.sol";
import {NATIVE} from "../../src/lib/CurrencyLibrary.sol";

contract ReactorTest is ReactorEvents, Test, PermitSignature, DeployPermit2 {
    using OrderInfoBuilder for OrderInfo;
    using MockOrderLib for MockOrder;
    using ArrayBuilder for uint256[];

    uint256 constant ONE = 10 ** 18;
    bytes4 constant INVALID_NONCE_SELECTOR = 0x756688fe;
    address internal constant PROTOCOL_FEE_OWNER = address(1);

    MockERC20 tokenIn;
    MockERC20 tokenOut;
    MockERC20 tokenOut2;
    MockFillContract fillContract;
    MockPreExecutionHook preExecutionHook;
    MockPostExecutionHook postExecutionHook;
    TokenTransferHook tokenTransferHook;
    IPermit2 permit2;
    MockFeeController feeController;
    address feeRecipient;
    Reactor reactor;
    MockAuctionResolver mockResolver;
    uint256 swapperPrivateKey;
    address swapper;

    function setUp() public {
        tokenIn = new MockERC20("Input", "IN", 18);
        tokenOut = new MockERC20("Output", "OUT", 18);
        tokenOut2 = new MockERC20("Output2", "OUT2", 18);
        swapperPrivateKey = 0x12341234;
        swapper = vm.addr(swapperPrivateKey);
        permit2 = IPermit2(deployPermit2());

        reactor = new Reactor(PROTOCOL_FEE_OWNER);
        preExecutionHook = new MockPreExecutionHook(permit2, reactor);
        preExecutionHook.setValid(true);
        postExecutionHook = new MockPostExecutionHook();
        tokenTransferHook = new TokenTransferHook(permit2, reactor);
        feeRecipient = makeAddr("feeRecipient");
        feeController = new MockFeeController(feeRecipient);
        mockResolver = new MockAuctionResolver();
        fillContract = new MockFillContract(address(reactor));
        vm.deal(address(fillContract), type(uint256).max);
    }

    /// @dev Create a signed order for Reactor using MockOrder
    function createAndSignOrder(MockOrder memory mockOrder)
        public
        view
        returns (SignedOrder memory signedOrder, bytes32 orderHash)
    {
        orderHash = mockOrder.hash();

        bytes memory sig = signOrder(swapperPrivateKey, address(permit2), mockOrder);

        bytes memory orderData = abi.encode(mockOrder);

        bytes memory encodedOrder = abi.encode(address(mockResolver), orderData);

        signedOrder = SignedOrder(encodedOrder, sig);
    }

    /// @dev Create many signed orders and return
    function createAndSignBatchOrders(MockOrder[] memory orders)
        public
        view
        returns (SignedOrder[] memory signedOrders, bytes32[] memory orderHashes)
    {
        signedOrders = new SignedOrder[](orders.length);
        orderHashes = new bytes32[](orders.length);
        for (uint256 i = 0; i < orders.length; i++) {
            (SignedOrder memory signed, bytes32 hash) = createAndSignOrder(orders[i]);
            signedOrders[i] = signed;
            orderHashes[i] = hash;
        }
    }

    /// @dev Helper to create a basic MockOrder with the standard token transfer hook
    function createBasicOrder(uint256 inputAmount, uint256 outputAmount, uint256 deadline)
        internal
        view
        returns (MockOrder memory)
    {
        return MockOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(deadline).withPreExecutionHook(
                tokenTransferHook
            ).withAuctionResolver(mockResolver),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(address(tokenOut), outputAmount, swapper)
        });
    }

    /// @dev Checkpoint token balances for assertions
    function _checkpointBalances()
        internal
        view
        returns (
            uint256 swapperInputBalance,
            uint256 fillContractInputBalance,
            uint256 swapperOutputBalance,
            uint256 fillContractOutputBalance
        )
    {
        swapperInputBalance = tokenIn.balanceOf(swapper);
        fillContractInputBalance = tokenIn.balanceOf(address(fillContract));
        swapperOutputBalance = tokenOut.balanceOf(swapper);
        fillContractOutputBalance = tokenOut.balanceOf(address(fillContract));
    }

    /// @dev Test of a simple execute
    function test_executeBaseCase() public {
        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;
        uint256 deadline = block.timestamp + 1000;

        tokenIn.mint(address(swapper), inputAmount);
        tokenOut.mint(address(fillContract), outputAmount);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        MockOrder memory order = createBasicOrder(inputAmount, outputAmount, deadline);

        (SignedOrder memory signedOrder, bytes32 orderHash) = createAndSignOrder(order);

        (
            uint256 swapperInputBalanceStart,
            uint256 fillContractInputBalanceStart,
            uint256 swapperOutputBalanceStart,
            uint256 fillContractOutputBalanceStart
        ) = _checkpointBalances();

        vm.expectEmit(true, true, true, true, address(reactor));
        emit Fill(orderHash, address(fillContract), swapper, order.info.nonce);
        fillContract.execute(signedOrder);
        vm.snapshotGasLastCall("ReactorExecuteSingle");

        assertEq(tokenIn.balanceOf(address(swapper)), swapperInputBalanceStart - inputAmount);
        assertEq(tokenIn.balanceOf(address(fillContract)), fillContractInputBalanceStart + inputAmount);
        assertEq(tokenOut.balanceOf(address(swapper)), swapperOutputBalanceStart + outputAmount);
        assertEq(tokenOut.balanceOf(address(fillContract)), fillContractOutputBalanceStart - outputAmount);
    }

    function test_executeWithFee() public {
        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;
        uint256 deadline = block.timestamp + 1000;
        uint8 feeBps = 3;

        vm.prank(PROTOCOL_FEE_OWNER);
        reactor.setProtocolFeeController(address(feeController));
        feeController.setFee(tokenIn, address(tokenOut), feeBps);
        tokenIn.mint(address(swapper), uint256(inputAmount) * 100);
        tokenOut.mint(address(fillContract), uint256(outputAmount) * 100);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        MockOrder memory order = createBasicOrder(inputAmount, outputAmount, deadline);

        (SignedOrder memory signedOrder, bytes32 orderHash) = createAndSignOrder(order);

        (
            uint256 swapperInputBalanceStart,
            uint256 fillContractInputBalanceStart,
            uint256 swapperOutputBalanceStart,
            uint256 fillContractOutputBalanceStart
        ) = _checkpointBalances();

        vm.expectEmit(true, true, true, true, address(reactor));
        emit Fill(orderHash, address(fillContract), swapper, order.info.nonce);
        fillContract.execute(signedOrder);
        vm.snapshotGasLastCall("BaseExecuteSingleWithFee");

        uint256 feeAmount = uint256(outputAmount) * feeBps / 10000;
        assertEq(tokenIn.balanceOf(address(swapper)), swapperInputBalanceStart - inputAmount);
        assertEq(tokenIn.balanceOf(address(fillContract)), fillContractInputBalanceStart + inputAmount);
        assertEq(tokenOut.balanceOf(address(swapper)), swapperOutputBalanceStart + outputAmount);
        assertEq(tokenOut.balanceOf(address(fillContract)), fillContractOutputBalanceStart - outputAmount - feeAmount);
        assertEq(tokenOut.balanceOf(address(feeRecipient)), feeAmount);
    }

    /// @dev Basic execute test for native currency output
    function test_executeNativeOutput() public {
        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;
        uint256 deadline = block.timestamp + 1000;

        tokenIn.mint(address(swapper), inputAmount);
        vm.deal(address(fillContract), outputAmount);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        MockOrder memory order = MockOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(deadline).withPreExecutionHook(
                tokenTransferHook
            ).withAuctionResolver(mockResolver),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(NATIVE, outputAmount, swapper)
        });

        (SignedOrder memory signedOrder,) = createAndSignOrder(order);

        uint256 swapperOutputBalanceStart = address(swapper).balance;
        uint256 fillContractOutputBalanceStart = address(fillContract).balance;
        (uint256 swapperInputBalanceStart, uint256 fillContractInputBalanceStart,,) = _checkpointBalances();

        fillContract.execute(signedOrder);
        vm.snapshotGasLastCall("ReactorExecuteSingleNativeOutput");

        assertEq(tokenIn.balanceOf(address(swapper)), swapperInputBalanceStart - inputAmount);
        assertEq(tokenIn.balanceOf(address(fillContract)), fillContractInputBalanceStart + inputAmount);
        assertEq(address(swapper).balance, swapperOutputBalanceStart + outputAmount);
        assertEq(address(fillContract).balance, fillContractOutputBalanceStart - outputAmount);
    }

    /// @dev Execute test with a pre-execution hook
    function test_executeWithPreExecutionHook() public {
        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;
        uint256 deadline = block.timestamp + 1000;

        tokenIn.mint(address(swapper), inputAmount);
        tokenOut.mint(address(fillContract), outputAmount);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        MockOrder memory order = MockOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(deadline).withPreExecutionHook(
                preExecutionHook
            ).withAuctionResolver(mockResolver),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(address(tokenOut), outputAmount, swapper)
        });

        (SignedOrder memory signedOrder,) = createAndSignOrder(order);

        (
            uint256 swapperInputBalanceStart,
            uint256 fillContractInputBalanceStart,
            uint256 swapperOutputBalanceStart,
            uint256 fillContractOutputBalanceStart
        ) = _checkpointBalances();

        uint256 counterBefore = preExecutionHook.preExecutionCounter();
        uint256 fillerExecutionsBefore = preExecutionHook.fillerExecutions(address(fillContract));

        fillContract.execute(signedOrder);
        vm.snapshotGasLastCall("ReactorExecuteSingleWithHook");

        // Verify hook was called and state was modified
        assertEq(preExecutionHook.preExecutionCounter(), counterBefore + 1);
        assertEq(preExecutionHook.fillerExecutions(address(fillContract)), fillerExecutionsBefore + 1);

        assertEq(tokenIn.balanceOf(address(swapper)), swapperInputBalanceStart - inputAmount);
        assertEq(tokenIn.balanceOf(address(fillContract)), fillContractInputBalanceStart + inputAmount);
        assertEq(tokenOut.balanceOf(address(swapper)), swapperOutputBalanceStart + outputAmount);
        assertEq(tokenOut.balanceOf(address(fillContract)), fillContractOutputBalanceStart - outputAmount);
    }

    /// @dev Test pre-execution hook that fails validation
    function test_executeWithPreExecutionHookRevert() public {
        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;
        uint256 deadline = block.timestamp + 1000;

        tokenIn.mint(address(swapper), inputAmount);
        tokenOut.mint(address(fillContract), outputAmount);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        // Set hook to invalid state
        preExecutionHook.setValid(false);

        MockOrder memory order = MockOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(deadline).withPreExecutionHook(
                preExecutionHook
            ).withAuctionResolver(mockResolver),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(address(tokenOut), outputAmount, swapper)
        });

        (SignedOrder memory signedOrder,) = createAndSignOrder(order);

        vm.expectRevert(MockPreExecutionHook.MockPreExecutionError.selector);
        fillContract.execute(signedOrder);
    }

    /// @dev Test execute with post-execution hook
    function test_executeWithPostExecutionHook() public {
        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;
        uint256 deadline = block.timestamp + 1000;

        tokenIn.mint(address(swapper), inputAmount);
        tokenOut.mint(address(fillContract), outputAmount);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        MockOrder memory order = MockOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(deadline).withPreExecutionHook(
                tokenTransferHook
            ).withPostExecutionHook(postExecutionHook).withAuctionResolver(mockResolver),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(address(tokenOut), outputAmount, swapper)
        });

        (SignedOrder memory signedOrder, bytes32 orderHash) = createAndSignOrder(order);

        uint256 counterBefore = postExecutionHook.postExecutionCounter();
        uint256 fillerExecutionsBefore = postExecutionHook.fillerExecutions(address(fillContract));
        uint256 swapperExecutionsBefore = postExecutionHook.swapperExecutions(swapper);

        fillContract.execute(signedOrder);

        // Verify post-hook was called
        assertEq(postExecutionHook.postExecutionCounter(), counterBefore + 1);
        assertEq(postExecutionHook.fillerExecutions(address(fillContract)), fillerExecutionsBefore + 1);
        assertEq(postExecutionHook.swapperExecutions(swapper), swapperExecutionsBefore + 1);
        assertEq(postExecutionHook.lastFiller(), address(fillContract));
        assertEq(postExecutionHook.lastSwapper(), swapper);
        assertEq(postExecutionHook.lastOrderHash(), orderHash);
        assertEq(postExecutionHook.lastInputAmount(), inputAmount);
        assertEq(postExecutionHook.lastOutputAmount(), outputAmount);

        // Verify tokens transferred correctly
        assertEq(tokenIn.balanceOf(address(swapper)), 0);
        assertEq(tokenIn.balanceOf(address(fillContract)), inputAmount);
        assertEq(tokenOut.balanceOf(address(swapper)), outputAmount);
        assertEq(tokenOut.balanceOf(address(fillContract)), 0);
    }

    /// @dev Test execute with post-execution hook that reverts
    function test_executeWithPostExecutionHookRevert() public {
        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;
        uint256 deadline = block.timestamp + 1000;

        tokenIn.mint(address(swapper), inputAmount);
        tokenOut.mint(address(fillContract), outputAmount);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        postExecutionHook.setShouldRevert(true);

        MockOrder memory order = MockOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(deadline).withPreExecutionHook(
                tokenTransferHook
            ).withPostExecutionHook(postExecutionHook).withAuctionResolver(mockResolver),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(address(tokenOut), outputAmount, swapper)
        });

        (SignedOrder memory signedOrder,) = createAndSignOrder(order);

        // Should revert with MockPostExecutionError
        vm.expectRevert(MockPostExecutionHook.MockPostExecutionError.selector);
        fillContract.execute(signedOrder);

        // Verify no tokens were transferred due to revert
        assertEq(tokenIn.balanceOf(address(swapper)), inputAmount);
        assertEq(tokenIn.balanceOf(address(fillContract)), 0);
        assertEq(tokenOut.balanceOf(address(swapper)), 0);
        assertEq(tokenOut.balanceOf(address(fillContract)), outputAmount);
    }

    /// @dev Test execute with both pre and post execution hooks
    function test_executeWithBothHooks() public {
        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;
        uint256 deadline = block.timestamp + 1000;

        tokenIn.mint(address(swapper), inputAmount);
        tokenOut.mint(address(fillContract), outputAmount);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        MockOrder memory order = MockOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(deadline).withPreExecutionHook(
                preExecutionHook
            ).withPostExecutionHook(postExecutionHook).withAuctionResolver(mockResolver),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(address(tokenOut), outputAmount, swapper)
        });

        (SignedOrder memory signedOrder,) = createAndSignOrder(order);

        uint256 preCounterBefore = preExecutionHook.preExecutionCounter();
        uint256 postCounterBefore = postExecutionHook.postExecutionCounter();

        fillContract.execute(signedOrder);

        // Verify both hooks were called
        assertEq(preExecutionHook.preExecutionCounter(), preCounterBefore + 1);
        assertEq(postExecutionHook.postExecutionCounter(), postCounterBefore + 1);
        assertEq(postExecutionHook.lastFiller(), address(fillContract));
        assertEq(postExecutionHook.lastSwapper(), swapper);
    }

    /// @dev Basic batch execute test
    function test_executeBatch() public {
        uint256 inputAmount = ONE;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn.mint(address(swapper), inputAmount * 3);
        tokenOut.mint(address(fillContract), 6 ether);
        tokenIn.forceApprove(swapper, address(permit2), type(uint256).max);

        uint256 totalOutputAmount = 3 * outputAmount;
        uint256 totalInputAmount = 3 * inputAmount;

        MockOrder[] memory orders = new MockOrder[](2);

        orders[0] = MockOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100).withNonce(
                0
            ).withPreExecutionHook(tokenTransferHook).withAuctionResolver(mockResolver),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(address(tokenOut), outputAmount, swapper)
        });

        orders[1] = MockOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100).withNonce(
                1
            ).withPreExecutionHook(tokenTransferHook).withAuctionResolver(mockResolver),
            input: InputToken(tokenIn, 2 * inputAmount, 2 * inputAmount),
            outputs: OutputsBuilder.single(address(tokenOut), 2 * outputAmount, swapper)
        });

        (SignedOrder[] memory signedOrders, bytes32[] memory orderHashes) = createAndSignBatchOrders(orders);

        vm.expectEmit(true, true, true, true);
        emit Fill(orderHashes[0], address(fillContract), swapper, orders[0].info.nonce);
        vm.expectEmit(true, true, true, true);
        emit Fill(orderHashes[1], address(fillContract), swapper, orders[1].info.nonce);

        fillContract.executeBatch(signedOrders);
        vm.snapshotGasLastCall("ReactorExecuteBatch");

        assertEq(tokenIn.balanceOf(address(swapper)), 0);
        assertEq(tokenIn.balanceOf(address(fillContract)), totalInputAmount);
        assertEq(tokenOut.balanceOf(address(swapper)), totalOutputAmount);
        assertEq(tokenOut.balanceOf(address(fillContract)), 6 ether - totalOutputAmount);
    }

    /// @dev Basic batch execute test with native output
    function test_executeBatchNativeOutput() public {
        uint256 inputAmount = ONE;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn.mint(address(swapper), inputAmount * 3);
        vm.deal(address(fillContract), 6 ether);
        tokenIn.forceApprove(swapper, address(permit2), type(uint256).max);

        uint256 totalOutputAmount = 3 * outputAmount;
        uint256 totalInputAmount = 3 * inputAmount;

        MockOrder[] memory orders = new MockOrder[](2);

        orders[0] = MockOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100).withNonce(
                0
            ).withPreExecutionHook(tokenTransferHook).withAuctionResolver(mockResolver),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(NATIVE, outputAmount, swapper)
        });

        orders[1] = MockOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100).withNonce(
                1
            ).withPreExecutionHook(tokenTransferHook).withAuctionResolver(mockResolver),
            input: InputToken(tokenIn, 2 * inputAmount, 2 * inputAmount),
            outputs: OutputsBuilder.single(NATIVE, 2 * outputAmount, swapper)
        });

        (SignedOrder[] memory signedOrders, bytes32[] memory orderHashes) = createAndSignBatchOrders(orders);

        vm.expectEmit(true, true, true, true);
        emit Fill(orderHashes[0], address(fillContract), swapper, orders[0].info.nonce);
        vm.expectEmit(true, true, true, true);
        emit Fill(orderHashes[1], address(fillContract), swapper, orders[1].info.nonce);

        fillContract.executeBatch(signedOrders);
        vm.snapshotGasLastCall("ReactorExecuteBatchNativeOutput");

        assertEq(address(swapper).balance, totalOutputAmount);
        assertEq(tokenIn.balanceOf(address(fillContract)), totalInputAmount);
    }

    /// @dev Test with multiple outputs
    function test_executeBatchMultipleOutputs() public {
        uint256 inputAmount = 3 ether;
        uint256[] memory outputAmounts = new uint256[](2);
        outputAmounts[0] = 2 ether;
        outputAmounts[1] = 1 ether;

        tokenIn.mint(address(swapper), inputAmount);
        tokenOut.mint(address(fillContract), 3 ether);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        MockOrder memory order = MockOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100)
                .withPreExecutionHook(tokenTransferHook).withAuctionResolver(mockResolver),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.multiple(address(tokenOut), outputAmounts, swapper)
        });

        (SignedOrder memory signedOrder, bytes32 orderHash) = createAndSignOrder(order);

        vm.expectEmit(true, true, true, true, address(reactor));
        emit Fill(orderHash, address(fillContract), swapper, order.info.nonce);

        fillContract.execute(signedOrder);

        assertEq(tokenIn.balanceOf(address(swapper)), 0);
        assertEq(tokenIn.balanceOf(address(fillContract)), inputAmount);
        assertEq(tokenOut.balanceOf(address(swapper)), 3 ether);
        assertEq(tokenOut.balanceOf(address(fillContract)), 0);
    }

    /// @dev Execute batch with multiple outputs using different tokens
    function test_executeBatchMultipleOutputsDifferentTokens() public {
        uint256[] memory output1 = ArrayBuilder.fill(1, 2 * ONE).push(ONE);
        uint256[] memory output2 = ArrayBuilder.fill(1, 3 * ONE).push(ONE);

        OutputToken[] memory outputs1 = OutputsBuilder.multiple(address(tokenOut), output1, swapper);
        outputs1[1].token = address(tokenOut2);

        OutputToken[] memory outputs2 = OutputsBuilder.multiple(address(tokenOut), output2, swapper);
        outputs2[0].token = address(tokenOut2);

        uint256 totalInputAmount = 3 * ONE;
        uint256 totalOutputAmount1 = 3 * ONE;
        uint256 totalOutputAmount2 = 4 * ONE;
        tokenIn.mint(address(swapper), totalInputAmount);
        tokenOut.mint(address(fillContract), totalOutputAmount1);
        tokenOut2.mint(address(fillContract), totalOutputAmount2);
        tokenIn.forceApprove(swapper, address(permit2), type(uint256).max);

        MockOrder[] memory orders = new MockOrder[](2);

        orders[0] = MockOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100).withNonce(
                0
            ).withPreExecutionHook(tokenTransferHook).withAuctionResolver(mockResolver),
            input: InputToken(tokenIn, ONE, ONE),
            outputs: outputs1
        });

        orders[1] = MockOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100).withNonce(
                1
            ).withPreExecutionHook(tokenTransferHook).withAuctionResolver(mockResolver),
            input: InputToken(tokenIn, ONE * 2, ONE * 2),
            outputs: outputs2
        });

        (SignedOrder[] memory signedOrders, bytes32[] memory orderHashes) = createAndSignBatchOrders(orders);
        vm.expectEmit(true, true, true, true);
        emit Fill(orderHashes[0], address(fillContract), swapper, orders[0].info.nonce);
        vm.expectEmit(true, true, true, true);
        emit Fill(orderHashes[1], address(fillContract), swapper, orders[1].info.nonce);

        fillContract.executeBatch(signedOrders);
        vm.snapshotGasLastCall("ReactorExecuteBatchMultipleOutputsDifferentTokens");

        assertEq(tokenOut.balanceOf(swapper), totalOutputAmount1);
        assertEq(tokenOut2.balanceOf(swapper), totalOutputAmount2);
        assertEq(tokenIn.balanceOf(address(fillContract)), totalInputAmount);
    }

    /// @dev Test executeBatch with post-execution hook
    function test_executeBatchWithPostExecutionHook() public {
        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;
        uint256 deadline = block.timestamp + 1000;

        // Create 3 orders
        MockOrder[] memory orders = new MockOrder[](3);
        for (uint256 i = 0; i < 3; i++) {
            tokenIn.mint(address(swapper), inputAmount);
            tokenOut.mint(address(fillContract), outputAmount);
            tokenIn.forceApprove(swapper, address(permit2), inputAmount * (i + 1));

            orders[i] = MockOrder({
                info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(deadline).withNonce(i)
                    .withPreExecutionHook(tokenTransferHook).withPostExecutionHook(postExecutionHook).withAuctionResolver(
                    mockResolver
                ),
                input: InputToken(tokenIn, inputAmount, inputAmount),
                outputs: OutputsBuilder.single(address(tokenOut), outputAmount, swapper)
            });
        }

        (SignedOrder[] memory signedOrders,) = createAndSignBatchOrders(orders);

        uint256 counterBefore = postExecutionHook.postExecutionCounter();

        fillContract.executeBatch(signedOrders);

        // Verify post-hook was called for each order
        assertEq(postExecutionHook.postExecutionCounter(), counterBefore + 3);
        assertEq(postExecutionHook.fillerExecutions(address(fillContract)), 3);
        assertEq(postExecutionHook.swapperExecutions(swapper), 3);
    }

    /// @dev Test invalid reactor error
    function test_executeInvalidReactor() public {
        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;
        uint256 deadline = block.timestamp + 1000;

        tokenIn.mint(address(swapper), inputAmount);
        tokenOut.mint(address(fillContract), outputAmount);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        // Create order with wrong reactor address
        MockOrder memory order = MockOrder({
            info: OrderInfoBuilder.init(address(0x1234)).withSwapper(swapper).withDeadline(deadline).withPreExecutionHook(
                tokenTransferHook
            ) // Wrong reactor
                .withAuctionResolver(mockResolver),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(address(tokenOut), outputAmount, swapper)
        });

        (SignedOrder memory signedOrder,) = createAndSignOrder(order);

        vm.expectRevert(IReactor.InvalidReactor.selector);
        fillContract.execute(signedOrder);
    }

    /// @dev Test missing pre-execution hook error
    function test_executeMissingHook() public {
        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;
        uint256 deadline = block.timestamp + 1000;

        tokenIn.mint(address(swapper), inputAmount);
        tokenOut.mint(address(fillContract), outputAmount);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        // Create order without a pre-execution hook
        MockOrder memory order = MockOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(deadline).withAuctionResolver(
                mockResolver
            ),
            // No preExecutionHook set
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(address(tokenOut), outputAmount, swapper)
        });

        (SignedOrder memory signedOrder,) = createAndSignOrder(order);

        vm.expectRevert(IReactor.MissingPreExecutionHook.selector);
        fillContract.execute(signedOrder);
    }

    /// @dev Test resolver substitution attack (ResolverMismatch error)
    function test_executeResolverMismatch() public {
        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;
        uint256 deadline = block.timestamp + 1000;

        tokenIn.mint(address(swapper), inputAmount);
        tokenOut.mint(address(fillContract), outputAmount);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        // Create order with mockResolver properly set in OrderInfo
        MockOrder memory order = MockOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(deadline).withPreExecutionHook(
                tokenTransferHook
            ).withAuctionResolver(mockResolver),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(address(tokenOut), outputAmount, swapper)
        });

        bytes memory sig = signOrder(swapperPrivateKey, address(permit2), order);
        bytes memory orderData = abi.encode(order);

        MockAuctionResolver maliciousResolver = new MockAuctionResolver();
        bytes memory encodedOrder = abi.encode(address(maliciousResolver), orderData);

        SignedOrder memory signedOrder = SignedOrder(encodedOrder, sig);

        vm.expectRevert(IReactor.ResolverMismatch.selector);
        fillContract.execute(signedOrder);
    }

    /// @dev Test deadline passed error
    function test_executeDeadlinePassed() public {
        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;
        uint256 deadline = block.timestamp - 1; // Past deadline

        tokenIn.mint(address(swapper), inputAmount);
        tokenOut.mint(address(fillContract), outputAmount);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        MockOrder memory order = createBasicOrder(inputAmount, outputAmount, deadline);
        (SignedOrder memory signedOrder,) = createAndSignOrder(order);

        vm.expectRevert(IReactor.DeadlinePassed.selector);
        fillContract.execute(signedOrder);
    }

    /// @dev Test signature replay protection
    function test_executeSignatureReplay() public {
        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;
        uint256 deadline = block.timestamp + 1000;

        tokenIn.mint(address(swapper), inputAmount * 2);
        tokenOut.mint(address(fillContract), outputAmount * 2);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount * 2);

        MockOrder memory order = createBasicOrder(inputAmount, outputAmount, deadline);
        (SignedOrder memory signedOrder,) = createAndSignOrder(order);

        fillContract.execute(signedOrder);

        // Try to replay - should fail with InvalidNonce since permit2 tracks nonce usage
        vm.expectRevert(INVALID_NONCE_SELECTOR);
        fillContract.execute(signedOrder);
    }

    /// @dev Basic execute fuzz test, checks balance before and after
    function testFuzz_execute(uint128 inputAmount, uint128 outputAmount, uint256 deadline) public {
        vm.assume(deadline > block.timestamp);
        vm.assume(inputAmount > 0);
        vm.assume(outputAmount > 0);

        // Seed both swapper and fillContract with enough tokens
        tokenIn.mint(address(swapper), uint256(inputAmount));
        tokenOut.mint(address(fillContract), uint256(outputAmount));
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        MockOrder memory order = MockOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(deadline).withPreExecutionHook(
                tokenTransferHook
            ).withAuctionResolver(mockResolver),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(address(tokenOut), outputAmount, swapper)
        });

        (SignedOrder memory signedOrder, bytes32 orderHash) = createAndSignOrder(order);

        (
            uint256 swapperInputBalanceStart,
            uint256 fillContractInputBalanceStart,
            uint256 swapperOutputBalanceStart,
            uint256 fillContractOutputBalanceStart
        ) = _checkpointBalances();

        vm.expectEmit(true, true, true, true, address(reactor));
        emit Fill(orderHash, address(fillContract), swapper, order.info.nonce);
        fillContract.execute(signedOrder);

        assertEq(tokenIn.balanceOf(address(swapper)), swapperInputBalanceStart - inputAmount);
        assertEq(tokenIn.balanceOf(address(fillContract)), fillContractInputBalanceStart + inputAmount);
        assertEq(tokenOut.balanceOf(address(swapper)), swapperOutputBalanceStart + outputAmount);
        assertEq(tokenOut.balanceOf(address(fillContract)), fillContractOutputBalanceStart - outputAmount);
    }

    /// @dev Fuzz test executeWithFee with protocol fees
    function testFuzz_executeWithFee(uint128 inputAmount, uint128 outputAmount, uint256 deadline, uint8 feeBps)
        public
    {
        vm.assume(deadline > block.timestamp);
        vm.assume(feeBps <= 5);
        vm.assume(inputAmount > 0);
        vm.assume(outputAmount > 0);

        vm.prank(PROTOCOL_FEE_OWNER);
        reactor.setProtocolFeeController(address(feeController));
        feeController.setFee(tokenIn, address(tokenOut), feeBps);
        tokenIn.mint(address(swapper), uint256(inputAmount));
        tokenOut.mint(address(fillContract), uint256(outputAmount) * 100);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        MockOrder memory order = MockOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(deadline).withPreExecutionHook(
                tokenTransferHook
            ).withAuctionResolver(mockResolver),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(address(tokenOut), outputAmount, swapper)
        });

        (SignedOrder memory signedOrder, bytes32 orderHash) = createAndSignOrder(order);

        (
            uint256 swapperInputBalanceStart,
            uint256 fillContractInputBalanceStart,
            uint256 swapperOutputBalanceStart,
            uint256 fillContractOutputBalanceStart
        ) = _checkpointBalances();

        vm.expectEmit(true, true, true, true, address(reactor));
        emit Fill(orderHash, address(fillContract), swapper, order.info.nonce);
        fillContract.execute(signedOrder);

        uint256 feeAmount = uint256(outputAmount) * feeBps / 10000;
        assertEq(tokenIn.balanceOf(address(swapper)), swapperInputBalanceStart - inputAmount);
        assertEq(tokenIn.balanceOf(address(fillContract)), fillContractInputBalanceStart + inputAmount);
        assertEq(tokenOut.balanceOf(address(swapper)), swapperOutputBalanceStart + outputAmount);
        assertEq(tokenOut.balanceOf(address(fillContract)), fillContractOutputBalanceStart - outputAmount - feeAmount);
        assertEq(tokenOut.balanceOf(address(feeRecipient)), feeAmount);
    }

    /// @dev Fuzz test for native currency output, checks balance before and after
    function testFuzz_executeNativeOutput(uint128 inputAmount, uint128 outputAmount, uint256 deadline) public {
        vm.assume(deadline > block.timestamp);
        vm.assume(inputAmount > 0);
        vm.assume(outputAmount > 0);

        tokenIn.mint(address(swapper), uint256(inputAmount));
        vm.deal(address(fillContract), uint256(outputAmount));
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        MockOrder memory order = MockOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(deadline).withPreExecutionHook(
                tokenTransferHook
            ).withAuctionResolver(mockResolver),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(NATIVE, outputAmount, swapper)
        });

        (SignedOrder memory signedOrder, bytes32 orderHash) = createAndSignOrder(order);

        uint256 swapperOutputBalanceStart = address(swapper).balance;
        uint256 fillContractOutputBalanceStart = address(fillContract).balance;
        (uint256 swapperInputBalanceStart, uint256 fillContractInputBalanceStart,,) = _checkpointBalances();

        vm.expectEmit(true, true, true, true, address(reactor));
        emit Fill(orderHash, address(fillContract), swapper, order.info.nonce);
        fillContract.execute(signedOrder);

        assertEq(tokenIn.balanceOf(address(swapper)), swapperInputBalanceStart - inputAmount);
        assertEq(tokenIn.balanceOf(address(fillContract)), fillContractInputBalanceStart + inputAmount);
        assertEq(address(swapper).balance, swapperOutputBalanceStart + outputAmount);
        assertEq(address(fillContract).balance, fillContractOutputBalanceStart - outputAmount);
    }

    /// @dev Fuzz test preExecutionHook with random amounts
    function testFuzz_executeWithPreExecutionHook(uint128 inputAmount, uint128 outputAmount, uint256 deadline) public {
        vm.assume(deadline > block.timestamp);
        vm.assume(inputAmount > 0);
        vm.assume(outputAmount > 0);

        tokenIn.mint(address(swapper), uint256(inputAmount));
        tokenOut.mint(address(fillContract), uint256(outputAmount));
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        MockOrder memory order = MockOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(deadline).withPreExecutionHook(
                preExecutionHook
            ).withAuctionResolver(mockResolver),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(address(tokenOut), outputAmount, swapper)
        });

        (SignedOrder memory signedOrder,) = createAndSignOrder(order);

        uint256 counterBefore = preExecutionHook.preExecutionCounter();
        uint256 fillerExecutionsBefore = preExecutionHook.fillerExecutions(address(fillContract));

        fillContract.execute(signedOrder);

        assertEq(preExecutionHook.preExecutionCounter(), counterBefore + 1);
        assertEq(preExecutionHook.fillerExecutions(address(fillContract)), fillerExecutionsBefore + 1);

        assertEq(tokenIn.balanceOf(address(swapper)), 0);
        assertEq(tokenIn.balanceOf(address(fillContract)), uint256(inputAmount));
        assertEq(tokenOut.balanceOf(address(swapper)), uint256(outputAmount));
        assertEq(tokenOut.balanceOf(address(fillContract)), 0);
    }

    /// @dev Fuzz test with post-execution hook
    function testFuzz_executeWithPostExecutionHook(uint128 inputAmount, uint128 outputAmount, uint256 deadline)
        public
    {
        vm.assume(deadline > block.timestamp);
        vm.assume(inputAmount > 0);
        vm.assume(outputAmount > 0);

        tokenIn.mint(address(swapper), uint256(inputAmount));
        tokenOut.mint(address(fillContract), uint256(outputAmount));
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        MockOrder memory order = MockOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(deadline).withPreExecutionHook(
                tokenTransferHook
            ).withPostExecutionHook(postExecutionHook).withAuctionResolver(mockResolver),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(address(tokenOut), outputAmount, swapper)
        });

        (SignedOrder memory signedOrder, bytes32 orderHash) = createAndSignOrder(order);

        uint256 counterBefore = postExecutionHook.postExecutionCounter();

        fillContract.execute(signedOrder);

        // Verify post-hook was called with correct data
        assertEq(postExecutionHook.postExecutionCounter(), counterBefore + 1);
        assertEq(postExecutionHook.lastFiller(), address(fillContract));
        assertEq(postExecutionHook.lastSwapper(), swapper);
        assertEq(postExecutionHook.lastOrderHash(), orderHash);
        assertEq(postExecutionHook.lastInputAmount(), uint256(inputAmount));
        assertEq(postExecutionHook.lastOutputAmount(), uint256(outputAmount));

        // Verify tokens transferred correctly
        assertEq(tokenIn.balanceOf(address(swapper)), 0);
        assertEq(tokenIn.balanceOf(address(fillContract)), uint256(inputAmount));
        assertEq(tokenOut.balanceOf(address(swapper)), uint256(outputAmount));
        assertEq(tokenOut.balanceOf(address(fillContract)), 0);
    }
}
