// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {DeployPermit2} from "../util/DeployPermit2.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {UnifiedReactor} from "../../src/v4/Reactor.sol";
import {IReactor} from "../../src/interfaces/IReactor.sol";
import {ReactorEvents} from "../../src/base/ReactorEvents.sol";
import {SignedOrder, InputToken, OutputToken} from "../../src/base/ReactorStructs.sol";
import {OrderInfo, ResolvedOrder} from "../../src/v4/base/ReactorStructs.sol";
import {OrderInfoBuilder} from "../v4/util/OrderInfoBuilder.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {MockFillContract} from "../v4/util/mock/MockFillContract.sol";
import {MockFillContractDoubleExecution} from "../util/mock/MockFillContractDoubleExecution.sol";
import {MockFillContractWithOutputOverride} from "../util/mock/MockFillContractWithOutputOverride.sol";
import {MockFeeController} from "../v4/util/mock/MockFeeController.sol";
import {MockPreExecutionHook} from "../v4/util/mock/MockPreExecutionHook.sol";
import {TokenTransferHook} from "../../src/v4/hooks/TokenTransferHook.sol";
import {MockAuctionResolver} from "./util/mock/MockAuctionResolver.sol";
import {MockOrder, MockOrderLib} from "./util/mock/MockOrderLib.sol";
import {ArrayBuilder} from "../util/ArrayBuilder.sol";
import {NATIVE} from "../../src/lib/CurrencyLibrary.sol";

contract UnifiedReactorTest is ReactorEvents, Test, PermitSignature, DeployPermit2 {
    using OrderInfoBuilder for OrderInfo;
    using MockOrderLib for MockOrder;
    using ArrayBuilder for uint256[];

    uint256 constant ONE = 10 ** 18;
    address internal constant PROTOCOL_FEE_OWNER = address(1);

    MockERC20 tokenIn;
    MockERC20 tokenOut;
    MockERC20 tokenOut2;
    MockFillContract fillContract;
    MockPreExecutionHook preExecutionHook;
    TokenTransferHook tokenTransferHook;
    IPermit2 permit2;
    MockFeeController feeController;
    address feeRecipient;
    UnifiedReactor reactor;
    MockAuctionResolver mockResolver;
    uint256 swapperPrivateKey;
    address swapper;

    error InvalidNonce();
    error InvalidSigner();
    error InvalidReactor();
    error DeadlinePassed();
    error MissingPreExecutionHook();

    function setUp() public {
        tokenIn = new MockERC20("Input", "IN", 18);
        tokenOut = new MockERC20("Output", "OUT", 18);
        tokenOut2 = new MockERC20("Output2", "OUT2", 18);
        swapperPrivateKey = 0x12341234;
        swapper = vm.addr(swapperPrivateKey);
        permit2 = IPermit2(deployPermit2());
        // Deploy hooks with permit2
        preExecutionHook = new MockPreExecutionHook(permit2);
        preExecutionHook.setValid(true);
        tokenTransferHook = new TokenTransferHook(permit2);
        feeRecipient = makeAddr("feeRecipient");
        feeController = new MockFeeController(feeRecipient);

        // Deploy UnifiedReactor
        reactor = new UnifiedReactor(permit2, PROTOCOL_FEE_OWNER);

        // Deploy mock resolver
        mockResolver = new MockAuctionResolver();

        // Deploy fill contract
        fillContract = new MockFillContract(address(reactor));

        // Provide ETH to fill contract for native transfers
        vm.deal(address(fillContract), type(uint256).max);
    }

    /// @dev Create a signed order for UnifiedReactor using MockOrder
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
            ),
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

        // Seed both swapper and fillContract with enough tokens
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
        // execute order
        fillContract.execute(signedOrder);
        vm.snapshotGasLastCall("UnifiedReactorExecuteSingle");

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
        // Seed both swapper and fillContract with enough tokens (important for dutch order)
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
        // execute order
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

        // Seed swapper with tokens and fillContract with ETH
        tokenIn.mint(address(swapper), inputAmount);
        vm.deal(address(fillContract), outputAmount);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        MockOrder memory order = MockOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(deadline).withPreExecutionHook(
                tokenTransferHook
            ),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(NATIVE, outputAmount, swapper)
        });

        (SignedOrder memory signedOrder,) = createAndSignOrder(order);

        uint256 swapperOutputBalanceStart = address(swapper).balance;
        uint256 fillContractOutputBalanceStart = address(fillContract).balance;
        (uint256 swapperInputBalanceStart, uint256 fillContractInputBalanceStart,,) = _checkpointBalances();

        // execute order
        fillContract.execute(signedOrder);
        vm.snapshotGasLastCall("UnifiedReactorExecuteSingleNativeOutput");

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

        // Seed both swapper and fillContract with enough tokens
        tokenIn.mint(address(swapper), inputAmount);
        tokenOut.mint(address(fillContract), outputAmount);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        // No need to set filler as valid - fillers are valid by default

        MockOrder memory order = MockOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(deadline).withPreExecutionHook(
                preExecutionHook
            ),
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

        // Check pre-execution hook state before
        uint256 counterBefore = preExecutionHook.preExecutionCounter();
        uint256 fillerExecutionsBefore = preExecutionHook.fillerExecutions(address(fillContract));

        // execute order
        fillContract.execute(signedOrder);
        vm.snapshotGasLastCall("UnifiedReactorExecuteSingleWithHook");

        // Verify hook was called and state was modified
        assertEq(preExecutionHook.preExecutionCounter(), counterBefore + 1);
        assertEq(preExecutionHook.fillerExecutions(address(fillContract)), fillerExecutionsBefore + 1);

        // Verify token transfers
        assertEq(tokenIn.balanceOf(address(swapper)), swapperInputBalanceStart - inputAmount);
        assertEq(tokenIn.balanceOf(address(fillContract)), fillContractInputBalanceStart + inputAmount);
        assertEq(tokenOut.balanceOf(address(swapper)), swapperOutputBalanceStart + outputAmount);
        assertEq(tokenOut.balanceOf(address(fillContract)), fillContractOutputBalanceStart - outputAmount);
    }

    /// @dev Test pre-execution hook that fails validation
    function test_executeWithPreExecutionHookFail() public {
        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;
        uint256 deadline = block.timestamp + 1000;

        // Seed both swapper and fillContract with enough tokens
        tokenIn.mint(address(swapper), inputAmount);
        tokenOut.mint(address(fillContract), outputAmount);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        // Set hook to invalid state
        preExecutionHook.setValid(false);

        MockOrder memory order = MockOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(deadline).withPreExecutionHook(
                preExecutionHook
            ),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(address(tokenOut), outputAmount, swapper)
        });

        (SignedOrder memory signedOrder,) = createAndSignOrder(order);

        vm.expectRevert(MockPreExecutionHook.MockPreExecutionError.selector);
        fillContract.execute(signedOrder);
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
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100)
                .withNonce(0).withPreExecutionHook(tokenTransferHook),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(address(tokenOut), outputAmount, swapper)
        });

        orders[1] = MockOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100)
                .withNonce(1).withPreExecutionHook(tokenTransferHook),
            input: InputToken(tokenIn, 2 * inputAmount, 2 * inputAmount),
            outputs: OutputsBuilder.single(address(tokenOut), 2 * outputAmount, swapper)
        });

        (SignedOrder[] memory signedOrders, bytes32[] memory orderHashes) = createAndSignBatchOrders(orders);

        vm.expectEmit(true, true, true, true);
        emit Fill(orderHashes[0], address(fillContract), swapper, orders[0].info.nonce);
        vm.expectEmit(true, true, true, true);
        emit Fill(orderHashes[1], address(fillContract), swapper, orders[1].info.nonce);

        fillContract.executeBatch(signedOrders);
        vm.snapshotGasLastCall("UnifiedReactorExecuteBatch");

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
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100)
                .withNonce(0).withPreExecutionHook(tokenTransferHook),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(NATIVE, outputAmount, swapper)
        });

        orders[1] = MockOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100)
                .withNonce(1).withPreExecutionHook(tokenTransferHook),
            input: InputToken(tokenIn, 2 * inputAmount, 2 * inputAmount),
            outputs: OutputsBuilder.single(NATIVE, 2 * outputAmount, swapper)
        });

        (SignedOrder[] memory signedOrders, bytes32[] memory orderHashes) = createAndSignBatchOrders(orders);

        vm.expectEmit(true, true, true, true);
        emit Fill(orderHashes[0], address(fillContract), swapper, orders[0].info.nonce);
        vm.expectEmit(true, true, true, true);
        emit Fill(orderHashes[1], address(fillContract), swapper, orders[1].info.nonce);

        fillContract.executeBatch(signedOrders);
        vm.snapshotGasLastCall("UnifiedReactorExecuteBatchNativeOutput");

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
                .withPreExecutionHook(tokenTransferHook),
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
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100)
                .withNonce(0).withPreExecutionHook(tokenTransferHook),
            input: InputToken(tokenIn, ONE, ONE),
            outputs: outputs1
        });

        orders[1] = MockOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100)
                .withNonce(1).withPreExecutionHook(tokenTransferHook),
            input: InputToken(tokenIn, ONE * 2, ONE * 2),
            outputs: outputs2
        });

        (SignedOrder[] memory signedOrders, bytes32[] memory orderHashes) = createAndSignBatchOrders(orders);
        vm.expectEmit(true, true, true, true);
        emit Fill(orderHashes[0], address(fillContract), swapper, orders[0].info.nonce);
        vm.expectEmit(true, true, true, true);
        emit Fill(orderHashes[1], address(fillContract), swapper, orders[1].info.nonce);

        fillContract.executeBatch(signedOrders);
        vm.snapshotGasLastCall("UnifiedReactorExecuteBatchMultipleOutputsDifferentTokens");

        assertEq(tokenOut.balanceOf(swapper), totalOutputAmount1);
        assertEq(tokenOut2.balanceOf(swapper), totalOutputAmount2);
        assertEq(tokenIn.balanceOf(address(fillContract)), totalInputAmount);
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
            info: OrderInfoBuilder.init(address(0x1234)).withSwapper(swapper).withDeadline(deadline) // Wrong reactor
                .withPreExecutionHook(tokenTransferHook),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(address(tokenOut), outputAmount, swapper)
        });

        (SignedOrder memory signedOrder,) = createAndSignOrder(order);

        vm.expectRevert(InvalidReactor.selector);
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
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(deadline),
            // No preExecutionHook set
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(address(tokenOut), outputAmount, swapper)
        });

        (SignedOrder memory signedOrder,) = createAndSignOrder(order);

        vm.expectRevert(MissingPreExecutionHook.selector);
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

        vm.expectRevert(DeadlinePassed.selector);
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

        // Execute once successfully
        fillContract.execute(signedOrder);

        // Try to replay - should fail with InvalidNonce since permit2 tracks nonce usage
        vm.expectRevert(InvalidNonce.selector);
        fillContract.execute(signedOrder);
    }

    /// @dev Test nonce reuse protection with different order parameters
    function test_nonceReuse() public {
        uint256 inputAmount = ONE;
        uint256 outputAmount = ONE * 2;
        tokenIn.mint(address(swapper), inputAmount * 100);
        tokenOut.mint(address(fillContract), outputAmount * 100);
        // approve for 2 orders here
        tokenIn.forceApprove(swapper, address(permit2), inputAmount * 2);

        MockOrder memory order = MockOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100)
                .withNonce(123).withPreExecutionHook(tokenTransferHook),
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

        // change deadline so sig and orderhash is different but nonce is the same
        order.info.deadline = block.timestamp + 101;
        (signedOrder, orderHash) = createAndSignOrder(order);
        vm.expectRevert(InvalidNonce.selector);
        fillContract.execute(signedOrder);
        vm.snapshotGasLastCall("UnifiedReactorRevertInvalidNonce");
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
            ),
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
        // execute order
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
        // Seed both swapper and fillContract with enough tokens (account for fees)
        tokenIn.mint(address(swapper), uint256(inputAmount));
        tokenOut.mint(address(fillContract), uint256(outputAmount) * 100);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        MockOrder memory order = MockOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(deadline).withPreExecutionHook(
                tokenTransferHook
            ),
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
        // execute order
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

        // Seed both swapper and fillContract with enough tokens
        tokenIn.mint(address(swapper), uint256(inputAmount));
        vm.deal(address(fillContract), uint256(outputAmount));
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        MockOrder memory order = MockOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(deadline).withPreExecutionHook(
                tokenTransferHook
            ),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(NATIVE, outputAmount, swapper)
        });

        (SignedOrder memory signedOrder, bytes32 orderHash) = createAndSignOrder(order);

        uint256 swapperOutputBalanceStart = address(swapper).balance;
        uint256 fillContractOutputBalanceStart = address(fillContract).balance;
        (uint256 swapperInputBalanceStart, uint256 fillContractInputBalanceStart,,) = _checkpointBalances();

        vm.expectEmit(true, true, true, true, address(reactor));
        emit Fill(orderHash, address(fillContract), swapper, order.info.nonce);
        // execute order
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

        // Seed both swapper and fillContract with enough tokens
        tokenIn.mint(address(swapper), uint256(inputAmount));
        tokenOut.mint(address(fillContract), uint256(outputAmount));
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        MockOrder memory order = MockOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(deadline).withPreExecutionHook(
                preExecutionHook
            ),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(address(tokenOut), outputAmount, swapper)
        });

        (SignedOrder memory signedOrder,) = createAndSignOrder(order);

        uint256 counterBefore = preExecutionHook.preExecutionCounter();
        uint256 fillerExecutionsBefore = preExecutionHook.fillerExecutions(address(fillContract));

        // execute order
        fillContract.execute(signedOrder);

        // Verify hook was called and state was modified
        assertEq(preExecutionHook.preExecutionCounter(), counterBefore + 1);
        assertEq(preExecutionHook.fillerExecutions(address(fillContract)), fillerExecutionsBefore + 1);

        // Verify token transfers
        assertEq(tokenIn.balanceOf(address(swapper)), 0);
        assertEq(tokenIn.balanceOf(address(fillContract)), uint256(inputAmount));
        assertEq(tokenOut.balanceOf(address(swapper)), uint256(outputAmount));
        assertEq(tokenOut.balanceOf(address(fillContract)), 0);
    }
}
