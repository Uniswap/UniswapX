// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {Test} from "forge-std/Test.sol";
import {BaseReactor} from "../../src/reactors/BaseReactor.sol";
import {MockValidationContract} from "../util/mock/MockValidationContract.sol";
import {ResolvedOrderLib} from "../../src/lib/ResolvedOrderLib.sol";
import {ReactorEvents} from "../../src/base/ReactorEvents.sol";
import {ResolvedOrder, SignedOrder, OrderInfo, InputToken, OutputToken} from "../../src/base/ReactorStructs.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {DeployPermit2} from "../util/DeployPermit2.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {ArrayBuilder} from "../util/ArrayBuilder.sol";
import {MockFeeController} from "../util/mock/MockFeeController.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {MockFillContract} from "../util/mock/MockFillContract.sol";
import {MockFillContractDoubleExecution} from "../util/mock/MockFillContractDoubleExecution.sol";
import {NATIVE} from "../../src/lib/CurrencyLibrary.sol";

abstract contract BaseReactorTest is GasSnapshot, ReactorEvents, Test, DeployPermit2 {
    using OrderInfoBuilder for OrderInfo;
    using ArrayBuilder for uint256[];
    using ArrayBuilder for uint256[][];

    uint256 constant ONE = 10 ** 18;
    address internal constant PROTOCOL_FEE_OWNER = address(1);

    MockERC20 tokenIn;
    MockERC20 tokenOut;
    MockERC20 tokenOut2;
    MockFillContract fillContract;
    MockValidationContract additionalValidationContract;
    IPermit2 permit2;
    MockFeeController feeController;
    address feeRecipient;
    BaseReactor reactor;
    uint256 swapperPrivateKey;
    address swapper;

    error InvalidNonce();
    error InvalidSigner();

    constructor() {
        tokenIn = new MockERC20("Input", "IN", 18);
        tokenOut = new MockERC20("Output", "OUT", 18);
        tokenOut2 = new MockERC20("Output2", "OUT2", 18);
        swapperPrivateKey = 0x12341234;
        swapper = vm.addr(swapperPrivateKey);
        permit2 = IPermit2(deployPermit2());
        additionalValidationContract = new MockValidationContract();
        additionalValidationContract.setValid(true);
        feeRecipient = makeAddr("feeRecipient");
        feeController = new MockFeeController(feeRecipient);
        reactor = createReactor();

        fillContract = new MockFillContract(address(reactor));
    }

    function name() public virtual returns (string memory) {}

    /// @dev Virtual function to create the specific reactor in state
    function createReactor() public virtual returns (BaseReactor) {}

    /// @dev Create a signed order and return the order and orderHash
    /// @param request Order to sign
    function createAndSignOrder(ResolvedOrder memory request)
        public
        virtual
        returns (SignedOrder memory signedOrder, bytes32 orderHash)
    {}

    /// @dev Create many signed orders and return
    /// @param requests Array of orders to sign
    function createAndSignBatchOrders(ResolvedOrder[] memory requests)
        public
        returns (SignedOrder[] memory signedOrders, bytes32[] memory orderHashes)
    {
        signedOrders = new SignedOrder[](requests.length);
        orderHashes = new bytes32[](requests.length);
        for (uint256 i = 0; i < requests.length; i++) {
            (SignedOrder memory signed, bytes32 hash) = createAndSignOrder(requests[i]);
            signedOrders[i] = signed;
            orderHashes[i] = hash;
        }
        return (signedOrders, orderHashes);
    }

    /// @dev Test of a simple execute
    function testBaseExecute() public {
        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;
        uint256 deadline = block.timestamp + 1000;
        // Seed both swapper and fillContract with enough tokens (important for dutch order)
        tokenIn.mint(address(swapper), uint256(inputAmount) * 100);
        tokenOut.mint(address(fillContract), uint256(outputAmount) * 100);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        ResolvedOrder memory order = ResolvedOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(deadline),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(address(tokenOut), outputAmount, swapper),
            sig: hex"00",
            hash: bytes32(0)
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
        _snapStart("ExecuteSingle");
        fillContract.execute(signedOrder);
        snapEnd();

        assertEq(tokenIn.balanceOf(address(swapper)), swapperInputBalanceStart - inputAmount);
        assertEq(tokenIn.balanceOf(address(fillContract)), fillContractInputBalanceStart + inputAmount);
        assertEq(tokenOut.balanceOf(address(swapper)), swapperOutputBalanceStart + outputAmount);
        assertEq(tokenOut.balanceOf(address(fillContract)), fillContractOutputBalanceStart - outputAmount);
    }

    /// @dev Basic execute test with protocol fee, checks balance before and after
    function testBaseExecuteWithFee() public {
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

        ResolvedOrder memory order = ResolvedOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(deadline),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(address(tokenOut), outputAmount, swapper),
            sig: hex"00",
            hash: bytes32(0)
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
        _snapStart("BaseExecuteSingleWithFee");
        fillContract.execute(signedOrder);
        snapEnd();

        uint256 feeAmount = uint256(outputAmount) * feeBps / 10000;
        assertEq(tokenIn.balanceOf(address(swapper)), swapperInputBalanceStart - inputAmount);
        assertEq(tokenIn.balanceOf(address(fillContract)), fillContractInputBalanceStart + inputAmount);
        assertEq(tokenOut.balanceOf(address(swapper)), swapperOutputBalanceStart + outputAmount);
        assertEq(tokenOut.balanceOf(address(fillContract)), fillContractOutputBalanceStart - outputAmount - feeAmount);
        assertEq(tokenOut.balanceOf(address(feeRecipient)), feeAmount);
    }

    /// @dev Basic execute test for native currency, checks balance before and after
    function testBaseExecuteNativeOutput() public {
        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;
        uint256 deadline = block.timestamp + 1000;
        // Seed both swapper and fillContract with enough tokens (important for dutch order)
        tokenIn.mint(address(swapper), uint256(inputAmount) * 100);
        vm.deal(address(fillContract), uint256(outputAmount) * 100);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        ResolvedOrder memory order = ResolvedOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(deadline),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(NATIVE, outputAmount, swapper),
            sig: hex"00",
            hash: bytes32(0)
        });

        (SignedOrder memory signedOrder, bytes32 orderHash) = createAndSignOrder(order);

        uint256 swapperOutputBalanceStart = address(swapper).balance;
        uint256 fillContractOutputBalanceStart = address(fillContract).balance;
        (uint256 swapperInputBalanceStart, uint256 fillContractInputBalanceStart,,) = _checkpointBalances();

        // TODO: expand to allow for custom callbackData in 3rd param
        vm.expectEmit(true, true, true, true, address(reactor));
        emit Fill(orderHash, address(fillContract), swapper, order.info.nonce);
        // execute order
        _snapStart("ExecuteSingleNativeOutput");
        fillContract.execute(signedOrder);
        snapEnd();

        assertEq(tokenIn.balanceOf(address(swapper)), swapperInputBalanceStart - inputAmount);
        assertEq(tokenIn.balanceOf(address(fillContract)), fillContractInputBalanceStart + inputAmount);
        assertEq(address(swapper).balance, swapperOutputBalanceStart + outputAmount);
        assertEq(address(fillContract).balance, fillContractOutputBalanceStart - outputAmount);
    }

    /// @dev Execute test with a succeeding validation contract
    function testBaseExecuteValidationContract() public {
        uint256 inputAmount = 1 ether;
        uint256 outputAmount = 1 ether;
        uint256 deadline = block.timestamp + 1000;
        vm.assume(deadline > block.timestamp);
        // Seed both swapper and fillContract with enough tokens (important for dutch order)
        tokenIn.mint(address(swapper), uint256(inputAmount) * 100);
        tokenOut.mint(address(fillContract), uint256(outputAmount) * 100);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        ResolvedOrder memory order = ResolvedOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(deadline).withValidationContract(
                additionalValidationContract
                ),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(address(tokenOut), outputAmount, swapper),
            sig: hex"00",
            hash: bytes32(0)
        });

        (SignedOrder memory signedOrder, bytes32 orderHash) = createAndSignOrder(order);

        (
            uint256 swapperInputBalanceStart,
            uint256 fillContractInputBalanceStart,
            uint256 swapperOutputBalanceStart,
            uint256 fillContractOutputBalanceStart
        ) = _checkpointBalances();

        // TODO: expand to allow for custom callbackData in 3rd param
        vm.expectEmit(true, true, true, true, address(reactor));
        emit Fill(orderHash, address(fillContract), swapper, order.info.nonce);
        // execute order
        _snapStart("ExecuteSingleValidation");
        fillContract.execute(signedOrder);
        snapEnd();

        assertEq(tokenIn.balanceOf(address(swapper)), swapperInputBalanceStart - inputAmount);
        assertEq(tokenIn.balanceOf(address(fillContract)), fillContractInputBalanceStart + inputAmount);
        assertEq(tokenOut.balanceOf(address(swapper)), swapperOutputBalanceStart + outputAmount);
        assertEq(tokenOut.balanceOf(address(fillContract)), fillContractOutputBalanceStart - outputAmount);
    }

    /// @dev Basic batch execute test
    // Two orders: (inputs = 1, outputs = 2), (inputs = 2, outputs = 4)
    function testBaseExecuteBatch() public {
        uint256 inputAmount = ONE;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn.mint(address(swapper), inputAmount * 3);
        tokenOut.mint(address(fillContract), 6 ether);
        tokenIn.forceApprove(swapper, address(permit2), type(uint256).max);

        uint256 totalOutputAmount = 3 * outputAmount;
        uint256 totalInputAmount = 3 * inputAmount;

        ResolvedOrder[] memory orders = new ResolvedOrder[](2);

        orders[0] = ResolvedOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100).withNonce(
                0
                ),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(address(tokenOut), outputAmount, swapper),
            sig: hex"00",
            hash: bytes32(0)
        });

        orders[1] = ResolvedOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100).withNonce(
                1
                ),
            input: InputToken(tokenIn, 2 * inputAmount, 2 * inputAmount),
            outputs: OutputsBuilder.single(address(tokenOut), 2 * outputAmount, swapper),
            sig: hex"00",
            hash: bytes32(0)
        });

        (SignedOrder[] memory signedOrders, bytes32[] memory orderHashes) = createAndSignBatchOrders(orders);
        vm.expectEmit(true, true, true, true);
        emit Fill(orderHashes[0], address(fillContract), swapper, orders[0].info.nonce);
        vm.expectEmit(true, true, true, true);
        emit Fill(orderHashes[1], address(fillContract), swapper, orders[1].info.nonce);

        _snapStart("ExecuteBatch");
        fillContract.executeBatch(signedOrders);
        snapEnd();

        assertEq(tokenOut.balanceOf(swapper), totalOutputAmount);
        assertEq(tokenIn.balanceOf(address(fillContract)), totalInputAmount);
    }

    /// @dev Basic batch execute test with native output
    function testBaseExecuteBatchNativeOutput() public {
        uint256 inputAmount = ONE;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn.mint(address(swapper), inputAmount * 3);
        vm.deal(address(fillContract), 6 ether);
        tokenIn.forceApprove(swapper, address(permit2), type(uint256).max);

        uint256 totalOutputAmount = 3 * outputAmount;
        uint256 totalInputAmount = 3 * inputAmount;

        ResolvedOrder[] memory orders = new ResolvedOrder[](2);

        orders[0] = ResolvedOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100).withNonce(
                0
                ),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(NATIVE, outputAmount, swapper),
            sig: hex"00",
            hash: bytes32(0)
        });

        orders[1] = ResolvedOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100).withNonce(
                1
                ),
            input: InputToken(tokenIn, 2 * inputAmount, 2 * inputAmount),
            outputs: OutputsBuilder.single(NATIVE, 2 * outputAmount, swapper),
            sig: hex"00",
            hash: bytes32(0)
        });

        (SignedOrder[] memory signedOrders, bytes32[] memory orderHashes) = createAndSignBatchOrders(orders);
        vm.expectEmit(true, true, true, true);
        emit Fill(orderHashes[0], address(fillContract), swapper, orders[0].info.nonce);
        vm.expectEmit(true, true, true, true);
        emit Fill(orderHashes[1], address(fillContract), swapper, orders[1].info.nonce);

        _snapStart("ExecuteBatchNativeOutput");
        fillContract.executeBatch(signedOrders);
        snapEnd();

        assertEq(swapper.balance, totalOutputAmount);
        assertEq(tokenIn.balanceOf(address(fillContract)), totalInputAmount);
    }

    /// @dev Execute batch with multiple outputs
    /// Order 1: (inputs = 1, outputs = [2, 1]),
    /// Order 2: (inputs = 2, outputs = [3])
    function testBaseExecuteBatchMultipleOutputs() public {
        uint256[] memory inputAmounts = ArrayBuilder.fill(1, ONE).push(2 * ONE);
        uint256[] memory output1 = ArrayBuilder.fill(1, 2 * ONE).push(ONE);
        uint256[] memory output2 = ArrayBuilder.fill(1, 3 * ONE);
        uint256[][] memory outputAmounts = ArrayBuilder.init(2, 1).set(0, output1).set(1, output2);

        uint256 totalOutputAmount = outputAmounts.sum();
        uint256 totalInputAmount = inputAmounts.sum();

        tokenIn.mint(address(swapper), totalInputAmount);
        tokenOut.mint(address(fillContract), totalOutputAmount);
        tokenIn.forceApprove(swapper, address(permit2), type(uint256).max);

        ResolvedOrder[] memory orders = new ResolvedOrder[](2);

        orders[0] = ResolvedOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100).withNonce(
                0
                ),
            input: InputToken(tokenIn, ONE, ONE),
            outputs: OutputsBuilder.multiple(address(tokenOut), output1, swapper),
            sig: hex"00",
            hash: bytes32(0)
        });

        orders[1] = ResolvedOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100).withNonce(
                1
                ),
            input: InputToken(tokenIn, ONE * 2, ONE * 2),
            outputs: OutputsBuilder.multiple(address(tokenOut), output2, swapper),
            sig: hex"00",
            hash: bytes32(0)
        });

        (SignedOrder[] memory signedOrders, bytes32[] memory orderHashes) = createAndSignBatchOrders(orders);
        vm.expectEmit(true, true, true, true);
        emit Fill(orderHashes[0], address(fillContract), swapper, orders[0].info.nonce);
        vm.expectEmit(true, true, true, true);
        emit Fill(orderHashes[1], address(fillContract), swapper, orders[1].info.nonce);

        _snapStart("ExecuteBatchMultipleOutputs");
        fillContract.executeBatch(signedOrders);
        snapEnd();

        assertEq(tokenOut.balanceOf(swapper), totalOutputAmount);
        assertEq(tokenIn.balanceOf(address(fillContract)), totalInputAmount);
    }

    /// @dev Execute batch with multiple outputs
    /// Order 1: (inputs = 1, outputs = [2, 1]),
    /// Order 2: (inputs = 2, outputs = [3])
    function testBaseExecuteBatchMultipleOutputsDifferentTokens() public {
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

        ResolvedOrder[] memory orders = new ResolvedOrder[](2);

        orders[0] = ResolvedOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100).withNonce(
                0
                ),
            input: InputToken(tokenIn, ONE, ONE),
            outputs: outputs1,
            sig: hex"00",
            hash: bytes32(0)
        });

        orders[1] = ResolvedOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100).withNonce(
                1
                ),
            input: InputToken(tokenIn, ONE * 2, ONE * 2),
            outputs: outputs2,
            sig: hex"00",
            hash: bytes32(0)
        });

        (SignedOrder[] memory signedOrders, bytes32[] memory orderHashes) = createAndSignBatchOrders(orders);
        vm.expectEmit(true, true, true, true);
        emit Fill(orderHashes[0], address(fillContract), swapper, orders[0].info.nonce);
        vm.expectEmit(true, true, true, true);
        emit Fill(orderHashes[1], address(fillContract), swapper, orders[1].info.nonce);

        _snapStart("ExecuteBatchMultipleOutputsDifferentTokens");
        fillContract.executeBatch(signedOrders);
        snapEnd();

        assertEq(tokenOut.balanceOf(swapper), totalOutputAmount1);
        assertEq(tokenOut2.balanceOf(swapper), totalOutputAmount2);
        assertEq(tokenIn.balanceOf(address(fillContract)), totalInputAmount);
    }

    /// @dev Base test preventing signatures from being reused
    function testBaseExecuteSignatureReplay() public {
        // Seed both swapper and fillContract with enough tokens
        uint256 inputAmount = ONE;
        uint256 outputAmount = ONE * 2;
        tokenIn.mint(address(swapper), inputAmount * 100);
        tokenOut.mint(address(fillContract), outputAmount * 100);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        ResolvedOrder memory order = ResolvedOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(address(tokenOut), outputAmount, swapper),
            sig: hex"00",
            hash: bytes32(0)
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

        tokenIn.mint(address(swapper), inputAmount);
        tokenOut.mint(address(fillContract), outputAmount);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        bytes memory oldSignature = signedOrder.sig;
        order.info.nonce = 1;
        // Create a new order, but use the previous signature
        (signedOrder, orderHash) = createAndSignOrder(order);
        signedOrder.sig = oldSignature;

        vm.expectRevert(InvalidSigner.selector);
        fillContract.execute(signedOrder);
    }

    /// @dev Base test preventing nonce reuse
    function testBaseNonceReuse() public {
        uint256 inputAmount = ONE;
        uint256 outputAmount = ONE * 2;
        tokenIn.mint(address(swapper), inputAmount * 100);
        tokenOut.mint(address(fillContract), outputAmount * 100);
        // approve for 2 orders here
        tokenIn.forceApprove(swapper, address(permit2), inputAmount * 2);

        ResolvedOrder memory order = ResolvedOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 100).withNonce(
                123
                ),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(address(tokenOut), outputAmount, swapper),
            sig: hex"00",
            hash: bytes32(0)
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
    }

    /// @dev Test executing two orders on two reactors at once
    /// @dev executing the second order inside the callback of the first's execution
    function testBaseExecuteTwoReactorsAtOnce() public {
        BaseReactor otherReactor = createReactor();
        MockFillContractDoubleExecution doubleExecutionFillContract =
            new MockFillContractDoubleExecution(address(reactor), address(otherReactor));
        // Seed both swapper and fillContract with enough tokens (important for dutch order)
        tokenIn.mint(address(swapper), 2 ether);
        tokenOut.mint(address(doubleExecutionFillContract), 2 ether);
        tokenIn.forceApprove(swapper, address(permit2), type(uint256).max);

        ResolvedOrder memory order1 = ResolvedOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 1000),
            input: InputToken(tokenIn, 1 ether, 1 ether),
            outputs: OutputsBuilder.single(address(tokenOut), 1 ether, swapper),
            sig: hex"00",
            hash: bytes32(0)
        });

        ResolvedOrder memory order2 = ResolvedOrder({
            info: OrderInfoBuilder.init(address(otherReactor)).withSwapper(swapper).withDeadline(block.timestamp + 1000)
                .withNonce(1234),
            input: InputToken(tokenIn, 1 ether, 1 ether),
            outputs: OutputsBuilder.single(address(tokenOut), 1 ether, swapper),
            sig: hex"00",
            hash: bytes32(0)
        });

        (SignedOrder memory signedOrder1, bytes32 orderHash1) = createAndSignOrder(order1);
        (SignedOrder memory signedOrder2, bytes32 orderHash2) = createAndSignOrder(order2);

        (uint256 swapperInputBalanceStart,, uint256 swapperOutputBalanceStart,) = _checkpointBalances();

        // TODO: expand to allow for custom callbackData in 3rd param
        vm.expectEmit(true, true, true, true, address(otherReactor));
        emit Fill(orderHash2, address(doubleExecutionFillContract), swapper, order2.info.nonce);
        vm.expectEmit(true, true, true, true, address(reactor));
        emit Fill(orderHash1, address(doubleExecutionFillContract), swapper, order1.info.nonce);
        doubleExecutionFillContract.execute(signedOrder1, signedOrder2);

        assertEq(tokenIn.balanceOf(address(swapper)), swapperInputBalanceStart - 2 ether);
        assertEq(tokenOut.balanceOf(address(swapper)), swapperOutputBalanceStart + 2 ether);
    }

    /// @dev Basic execute test with protocol fee, checks balance before and after
    function testBaseExecuteWithFee(uint128 inputAmount, uint128 outputAmount, uint256 deadline, uint8 feeBps) public {
        vm.assume(deadline > block.timestamp);
        vm.assume(feeBps <= 5);

        vm.prank(PROTOCOL_FEE_OWNER);
        reactor.setProtocolFeeController(address(feeController));
        feeController.setFee(tokenIn, address(tokenOut), feeBps);
        // Seed both swapper and fillContract with enough tokens (important for dutch order)
        tokenIn.mint(address(swapper), uint256(inputAmount) * 100);
        tokenOut.mint(address(fillContract), uint256(outputAmount) * 100);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        ResolvedOrder memory order = ResolvedOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(deadline),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(address(tokenOut), outputAmount, swapper),
            sig: hex"00",
            hash: bytes32(0)
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

    /// @dev Basic execute test, checks balance before and after
    function testBaseExecute(uint128 inputAmount, uint128 outputAmount, uint256 deadline) public {
        vm.assume(deadline > block.timestamp);
        // Seed both swapper and fillContract with enough tokens (important for dutch order)
        tokenIn.mint(address(swapper), uint256(inputAmount) * 100);
        tokenOut.mint(address(fillContract), uint256(outputAmount) * 100);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        ResolvedOrder memory order = ResolvedOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(deadline),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(address(tokenOut), outputAmount, swapper),
            sig: hex"00",
            hash: bytes32(0)
        });

        (SignedOrder memory signedOrder, bytes32 orderHash) = createAndSignOrder(order);

        (
            uint256 swapperInputBalanceStart,
            uint256 fillContractInputBalanceStart,
            uint256 swapperOutputBalanceStart,
            uint256 fillContractOutputBalanceStart
        ) = _checkpointBalances();

        // TODO: expand to allow for custom callbackData in 3rd param
        vm.expectEmit(true, true, true, true, address(reactor));
        emit Fill(orderHash, address(fillContract), swapper, order.info.nonce);
        // execute order
        fillContract.execute(signedOrder);

        assertEq(tokenIn.balanceOf(address(swapper)), swapperInputBalanceStart - inputAmount);
        assertEq(tokenIn.balanceOf(address(fillContract)), fillContractInputBalanceStart + inputAmount);
        assertEq(tokenOut.balanceOf(address(swapper)), swapperOutputBalanceStart + outputAmount);
        assertEq(tokenOut.balanceOf(address(fillContract)), fillContractOutputBalanceStart - outputAmount);
    }

    /// @dev Execute with a succeeding validation contract
    function testBaseExecuteValidationContract(uint128 inputAmount, uint128 outputAmount, uint256 deadline) public {
        vm.assume(deadline > block.timestamp);
        // Seed both swapper and fillContract with enough tokens (important for dutch order)
        tokenIn.mint(address(swapper), uint256(inputAmount) * 100);
        tokenOut.mint(address(fillContract), uint256(outputAmount) * 100);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        ResolvedOrder memory order = ResolvedOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(deadline).withValidationContract(
                additionalValidationContract
                ),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(address(tokenOut), outputAmount, swapper),
            sig: hex"00",
            hash: bytes32(0)
        });

        (SignedOrder memory signedOrder, bytes32 orderHash) = createAndSignOrder(order);

        (
            uint256 swapperInputBalanceStart,
            uint256 fillContractInputBalanceStart,
            uint256 swapperOutputBalanceStart,
            uint256 fillContractOutputBalanceStart
        ) = _checkpointBalances();

        // TODO: expand to allow for custom callbackData in 3rd param
        vm.expectEmit(true, true, true, true, address(reactor));
        emit Fill(orderHash, address(fillContract), swapper, order.info.nonce);
        // execute order
        fillContract.execute(signedOrder);

        assertEq(tokenIn.balanceOf(address(swapper)), swapperInputBalanceStart - inputAmount);
        assertEq(tokenIn.balanceOf(address(fillContract)), fillContractInputBalanceStart + inputAmount);
        assertEq(tokenOut.balanceOf(address(swapper)), swapperOutputBalanceStart + outputAmount);
        assertEq(tokenOut.balanceOf(address(fillContract)), fillContractOutputBalanceStart - outputAmount);
    }

    /// @dev Execute with a failing validation contract
    function testBaseExecuteValidationContractFail(uint128 inputAmount, uint128 outputAmount, uint256 deadline)
        public
    {
        vm.assume(deadline > block.timestamp);
        // Seed both swapper and fillContract with enough tokens (important for dutch order)
        tokenIn.mint(address(swapper), uint256(inputAmount) * 100);
        tokenOut.mint(address(fillContract), uint256(outputAmount) * 100);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);
        additionalValidationContract.setValid(false);

        ResolvedOrder memory order = ResolvedOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(deadline).withValidationContract(
                additionalValidationContract
                ),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(address(tokenOut), outputAmount, swapper),
            sig: hex"00",
            hash: bytes32(0)
        });

        (SignedOrder memory signedOrder,) = createAndSignOrder(order);

        vm.expectRevert(MockValidationContract.MockValidationError.selector);
        fillContract.execute(signedOrder);
    }

    /// @dev Execute with an invalid reactor
    function testBaseExecuteInvalidReactor(
        address orderReactor,
        uint128 inputAmount,
        uint128 outputAmount,
        uint256 deadline
    ) public {
        vm.assume(deadline > block.timestamp);
        vm.assume(orderReactor != address(reactor));
        // Seed both swapper and fillContract with enough tokens (important for dutch order)
        tokenIn.mint(address(swapper), uint256(inputAmount) * 100);
        tokenOut.mint(address(fillContract), uint256(outputAmount) * 100);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        ResolvedOrder memory order = ResolvedOrder({
            info: OrderInfoBuilder.init(orderReactor).withSwapper(swapper).withDeadline(deadline).withValidationContract(
                additionalValidationContract
                ),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(address(tokenOut), outputAmount, swapper),
            sig: hex"00",
            hash: bytes32(0)
        });

        (SignedOrder memory signedOrder,) = createAndSignOrder(order);

        vm.expectRevert(ResolvedOrderLib.InvalidReactor.selector);
        fillContract.execute(signedOrder);
    }

    /// @dev Execute with a deadline already passed
    function testBaseExecuteDeadlinePassed(uint128 inputAmount, uint128 outputAmount, uint256 deadline) public {
        vm.assume(deadline < block.timestamp);
        // Seed both swapper and fillContract with enough tokens (important for dutch order)
        tokenIn.mint(address(swapper), uint256(inputAmount) * 100);
        tokenOut.mint(address(fillContract), uint256(outputAmount) * 100);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        ResolvedOrder memory order = ResolvedOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(deadline).withValidationContract(
                additionalValidationContract
                ),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(address(tokenOut), outputAmount, swapper),
            sig: hex"00",
            hash: bytes32(0)
        });

        (SignedOrder memory signedOrder,) = createAndSignOrder(order);

        // cannot enforce selector as some reactors early throw in this case
        vm.expectRevert();
        fillContract.execute(signedOrder);
    }

    /// @dev Basic execute test for native currency, checks balance before and after
    function testBaseExecuteNativeOutput(uint128 inputAmount, uint128 outputAmount, uint256 deadline) public {
        vm.assume(deadline > block.timestamp);
        // Seed both swapper and fillContract with enough tokens (important for dutch order)
        tokenIn.mint(address(swapper), uint256(inputAmount) * 100);
        vm.deal(address(fillContract), uint256(outputAmount) * 100);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        ResolvedOrder memory order = ResolvedOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(deadline),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: OutputsBuilder.single(NATIVE, outputAmount, swapper),
            sig: hex"00",
            hash: bytes32(0)
        });

        (SignedOrder memory signedOrder, bytes32 orderHash) = createAndSignOrder(order);

        uint256 swapperOutputBalanceStart = address(swapper).balance;
        uint256 fillContractOutputBalanceStart = address(fillContract).balance;
        (uint256 swapperInputBalanceStart, uint256 fillContractInputBalanceStart,,) = _checkpointBalances();

        // TODO: expand to allow for custom callbackData in 3rd param
        vm.expectEmit(true, true, true, true, address(reactor));
        emit Fill(orderHash, address(fillContract), swapper, order.info.nonce);
        // execute order
        fillContract.execute(signedOrder);

        assertEq(tokenIn.balanceOf(address(swapper)), swapperInputBalanceStart - inputAmount);
        assertEq(tokenIn.balanceOf(address(fillContract)), fillContractInputBalanceStart + inputAmount);
        assertEq(address(swapper).balance, swapperOutputBalanceStart + outputAmount);
        assertEq(address(fillContract).balance, fillContractOutputBalanceStart - outputAmount);
    }

    function _checkpointBalances()
        internal
        view
        returns (
            uint256 swapperInputBalanceStart,
            uint256 fillContractInputBalanceStart,
            uint256 swapperOutputBalanceStart,
            uint256 fillContractOutputBalanceStart
        )
    {
        swapperInputBalanceStart = tokenIn.balanceOf(address(swapper));
        fillContractInputBalanceStart = tokenIn.balanceOf(address(fillContract));
        swapperOutputBalanceStart = tokenOut.balanceOf(address(swapper));
        fillContractOutputBalanceStart = tokenOut.balanceOf(address(fillContract));
    }

    function _snapStart(string memory testName) internal {
        snapStart(string.concat("Base-", name(), "-", testName));
    }
}
