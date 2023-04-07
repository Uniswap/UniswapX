// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {Test} from "forge-std/Test.sol";
import {NATIVE} from "../../src/lib/CurrencyLibrary.sol";
import {BaseReactor} from "../../src/reactors/BaseReactor.sol";
import {MockValidationContract} from "../util/mock/MockValidationContract.sol";
import {ResolvedOrderLib} from "../../src/lib/ResolvedOrderLib.sol";
import {ReactorEvents} from "../../src/base/ReactorEvents.sol";
import {ResolvedOrder, SignedOrder, OrderInfo, InputToken, OutputToken} from "../../src/base/ReactorStructs.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {DeployPermit2} from "../util/DeployPermit2.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {ArrayBuilder} from "../util/ArrayBuilder.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {MockFillContract} from "../util/mock/MockFillContract.sol";

abstract contract BaseReactorTest is GasSnapshot, ReactorEvents, Test, DeployPermit2 {
    using OrderInfoBuilder for OrderInfo;
    using ArrayBuilder for uint256[];
    using ArrayBuilder for uint256[][];

    uint256 constant ONE = 10 ** 18;

    MockERC20 tokenIn;
    MockERC20 tokenOut;
    MockERC20 tokenOut2;
    MockFillContract fillContract;
    MockValidationContract validationContract;
    ISignatureTransfer permit2;
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
        permit2 = ISignatureTransfer(deployPermit2());
        fillContract = new MockFillContract();
        validationContract = new MockValidationContract();
        validationContract.setValid(true);
        createReactor();
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

    /// @dev Basic execute test, checks balance before and after
    function testBaseExecute(uint128 inputAmount, uint128 outputAmount, uint256 deadline) public {
        vm.assume(deadline > block.timestamp);
        // Seed both swapper and fillContract with enough tokens (important for dutch order)
        tokenIn.mint(address(swapper), uint256(inputAmount) * 100);
        tokenOut.mint(address(fillContract), uint256(outputAmount) * 100);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        ResolvedOrder memory order = ResolvedOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(swapper).withDeadline(deadline),
            input: InputToken(address(tokenIn), inputAmount, inputAmount),
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

        // TODO: expand to allow for custom fillData in 3rd param
        vm.expectEmit(true, true, true, true, address(reactor));
        emit Fill(orderHash, address(this), swapper, order.info.nonce);
        // execute order
        _snapStart("ExecuteSingle");
        reactor.execute(signedOrder, address(fillContract), bytes(""));
        snapEnd();

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
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(swapper).withDeadline(deadline).withValidationContract(
                address(validationContract)
                ),
            input: InputToken(address(tokenIn), inputAmount, inputAmount),
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

        // TODO: expand to allow for custom fillData in 3rd param
        vm.expectEmit(true, true, true, true, address(reactor));
        emit Fill(orderHash, address(this), swapper, order.info.nonce);
        // execute order
        _snapStart("ExecuteSingleValidation");
        reactor.execute(signedOrder, address(fillContract), bytes(""));
        snapEnd();

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
        validationContract.setValid(false);

        ResolvedOrder memory order = ResolvedOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(swapper).withDeadline(deadline).withValidationContract(
                address(validationContract)
                ),
            input: InputToken(address(tokenIn), inputAmount, inputAmount),
            outputs: OutputsBuilder.single(address(tokenOut), outputAmount, swapper),
            sig: hex"00",
            hash: bytes32(0)
        });

        (SignedOrder memory signedOrder,) = createAndSignOrder(order);

        vm.expectRevert(ResolvedOrderLib.ValidationFailed.selector);
        reactor.execute(signedOrder, address(fillContract), bytes(""));
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
            info: OrderInfoBuilder.init(orderReactor).withOfferer(swapper).withDeadline(deadline).withValidationContract(
                address(validationContract)
                ),
            input: InputToken(address(tokenIn), inputAmount, inputAmount),
            outputs: OutputsBuilder.single(address(tokenOut), outputAmount, swapper),
            sig: hex"00",
            hash: bytes32(0)
        });

        (SignedOrder memory signedOrder,) = createAndSignOrder(order);

        vm.expectRevert(ResolvedOrderLib.InvalidReactor.selector);
        reactor.execute(signedOrder, address(fillContract), bytes(""));
    }

    /// @dev Execute with a deadline already passed
    function testBaseExecuteDeadlinePassed(uint128 inputAmount, uint128 outputAmount, uint256 deadline) public {
        vm.assume(deadline < block.timestamp);
        // Seed both swapper and fillContract with enough tokens (important for dutch order)
        tokenIn.mint(address(swapper), uint256(inputAmount) * 100);
        tokenOut.mint(address(fillContract), uint256(outputAmount) * 100);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        ResolvedOrder memory order = ResolvedOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(swapper).withDeadline(deadline).withValidationContract(
                address(validationContract)
                ),
            input: InputToken(address(tokenIn), inputAmount, inputAmount),
            outputs: OutputsBuilder.single(address(tokenOut), outputAmount, swapper),
            sig: hex"00",
            hash: bytes32(0)
        });

        (SignedOrder memory signedOrder,) = createAndSignOrder(order);

        // cannot enforce selector as some reactors early throw in this case
        vm.expectRevert();
        reactor.execute(signedOrder, address(fillContract), bytes(""));
    }

    /// @dev Basic execute test for native currency, checks balance before and after
    function testBaseExecuteNativeOutput(uint128 inputAmount, uint128 outputAmount, uint256 deadline) public {
        vm.assume(deadline > block.timestamp);
        // Seed both swapper and fillContract with enough tokens (important for dutch order)
        tokenIn.mint(address(swapper), uint256(inputAmount) * 100);
        vm.deal(address(fillContract), uint256(outputAmount) * 100);
        tokenIn.forceApprove(swapper, address(permit2), inputAmount);

        ResolvedOrder memory order = ResolvedOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(swapper).withDeadline(deadline),
            input: InputToken(address(tokenIn), inputAmount, inputAmount),
            outputs: OutputsBuilder.single(NATIVE, outputAmount, swapper),
            sig: hex"00",
            hash: bytes32(0)
        });

        (SignedOrder memory signedOrder, bytes32 orderHash) = createAndSignOrder(order);

        uint256 swapperOutputBalanceStart = address(swapper).balance;
        uint256 fillContractOutputBalanceStart = address(fillContract).balance;
        (uint256 swapperInputBalanceStart, uint256 fillContractInputBalanceStart,,) = _checkpointBalances();

        // TODO: expand to allow for custom fillData in 3rd param
        vm.expectEmit(true, true, true, true, address(reactor));
        emit Fill(orderHash, address(this), swapper, order.info.nonce);
        // execute order
        _snapStart("ExecuteSingleNativeOutput");
        reactor.execute(signedOrder, address(fillContract), bytes(""));
        snapEnd();

        assertEq(tokenIn.balanceOf(address(swapper)), swapperInputBalanceStart - inputAmount);
        assertEq(tokenIn.balanceOf(address(fillContract)), fillContractInputBalanceStart + inputAmount);
        assertEq(address(swapper).balance, swapperOutputBalanceStart + outputAmount);
        assertEq(address(fillContract).balance, fillContractOutputBalanceStart - outputAmount);
    }

    /// @dev Basic batch execute test
    // Two orders: (inputs = 1, outputs = 2), (inputs = 2, outputs = 4)
    function testBaseExecuteBatch() public {
        uint256 inputAmount = ONE;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn.mint(address(swapper), inputAmount * 3);
        tokenOut.mint(address(fillContract), 6 * 10 ** 18);
        tokenIn.forceApprove(swapper, address(permit2), type(uint256).max);

        uint256 totalOutputAmount = 3 * outputAmount;
        uint256 totalInputAmount = 3 * inputAmount;

        ResolvedOrder[] memory orders = new ResolvedOrder[](2);

        orders[0] = ResolvedOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(swapper).withDeadline(block.timestamp + 100).withNonce(
                0
                ),
            input: InputToken(address(tokenIn), inputAmount, inputAmount),
            outputs: OutputsBuilder.single(address(tokenOut), outputAmount, swapper),
            sig: hex"00",
            hash: bytes32(0)
        });

        orders[1] = ResolvedOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(swapper).withDeadline(block.timestamp + 100).withNonce(
                1
                ),
            input: InputToken(address(tokenIn), 2 * inputAmount, 2 * inputAmount),
            outputs: OutputsBuilder.single(address(tokenOut), 2 * outputAmount, swapper),
            sig: hex"00",
            hash: bytes32(0)
        });

        (SignedOrder[] memory signedOrders, bytes32[] memory orderHashes) = createAndSignBatchOrders(orders);
        vm.expectEmit(true, true, true, true);
        emit Fill(orderHashes[0], address(this), swapper, orders[0].info.nonce);
        vm.expectEmit(true, true, true, true);
        emit Fill(orderHashes[1], address(this), swapper, orders[1].info.nonce);

        _snapStart("ExecuteBatch");
        reactor.executeBatch(signedOrders, address(fillContract), bytes(""));
        snapEnd();

        assertEq(tokenOut.balanceOf(swapper), totalOutputAmount);
        assertEq(tokenIn.balanceOf(address(fillContract)), totalInputAmount);
    }

    /// @dev Basic batch execute test with native output
    function testBaseExecuteBatchNativeOutput() public {
        uint256 inputAmount = ONE;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn.mint(address(swapper), inputAmount * 3);
        vm.deal(address(fillContract), 6 * 10 ** 18);
        tokenIn.forceApprove(swapper, address(permit2), type(uint256).max);

        uint256 totalOutputAmount = 3 * outputAmount;
        uint256 totalInputAmount = 3 * inputAmount;

        ResolvedOrder[] memory orders = new ResolvedOrder[](2);

        orders[0] = ResolvedOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(swapper).withDeadline(block.timestamp + 100).withNonce(
                0
                ),
            input: InputToken(address(tokenIn), inputAmount, inputAmount),
            outputs: OutputsBuilder.single(NATIVE, outputAmount, swapper),
            sig: hex"00",
            hash: bytes32(0)
        });

        orders[1] = ResolvedOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(swapper).withDeadline(block.timestamp + 100).withNonce(
                1
                ),
            input: InputToken(address(tokenIn), 2 * inputAmount, 2 * inputAmount),
            outputs: OutputsBuilder.single(NATIVE, 2 * outputAmount, swapper),
            sig: hex"00",
            hash: bytes32(0)
        });

        (SignedOrder[] memory signedOrders, bytes32[] memory orderHashes) = createAndSignBatchOrders(orders);
        vm.expectEmit(true, true, true, true);
        emit Fill(orderHashes[0], address(this), swapper, orders[0].info.nonce);
        vm.expectEmit(true, true, true, true);
        emit Fill(orderHashes[1], address(this), swapper, orders[1].info.nonce);

        _snapStart("ExecuteBatchNativeOutput");
        reactor.executeBatch(signedOrders, address(fillContract), bytes(""));
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
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(swapper).withDeadline(block.timestamp + 100).withNonce(
                0
                ),
            input: InputToken(address(tokenIn), ONE, ONE),
            outputs: OutputsBuilder.multiple(address(tokenOut), output1, swapper),
            sig: hex"00",
            hash: bytes32(0)
        });

        orders[1] = ResolvedOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(swapper).withDeadline(block.timestamp + 100).withNonce(
                1
                ),
            input: InputToken(address(tokenIn), ONE * 2, ONE * 2),
            outputs: OutputsBuilder.multiple(address(tokenOut), output2, swapper),
            sig: hex"00",
            hash: bytes32(0)
        });

        (SignedOrder[] memory signedOrders, bytes32[] memory orderHashes) = createAndSignBatchOrders(orders);
        vm.expectEmit(true, true, true, true);
        emit Fill(orderHashes[0], address(this), swapper, orders[0].info.nonce);
        vm.expectEmit(true, true, true, true);
        emit Fill(orderHashes[1], address(this), swapper, orders[1].info.nonce);

        _snapStart("ExecuteBatchMultipleOutputs");
        reactor.executeBatch(signedOrders, address(fillContract), bytes(""));
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
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(swapper).withDeadline(block.timestamp + 100).withNonce(
                0
                ),
            input: InputToken(address(tokenIn), ONE, ONE),
            outputs: outputs1,
            sig: hex"00",
            hash: bytes32(0)
        });

        orders[1] = ResolvedOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(swapper).withDeadline(block.timestamp + 100).withNonce(
                1
                ),
            input: InputToken(address(tokenIn), ONE * 2, ONE * 2),
            outputs: outputs2,
            sig: hex"00",
            hash: bytes32(0)
        });

        (SignedOrder[] memory signedOrders, bytes32[] memory orderHashes) = createAndSignBatchOrders(orders);
        vm.expectEmit(true, true, true, true);
        emit Fill(orderHashes[0], address(this), swapper, orders[0].info.nonce);
        vm.expectEmit(true, true, true, true);
        emit Fill(orderHashes[1], address(this), swapper, orders[1].info.nonce);

        _snapStart("ExecuteBatchMultipleOutputsDifferentTokens");
        reactor.executeBatch(signedOrders, address(fillContract), bytes(""));
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
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(swapper).withDeadline(block.timestamp + 100),
            input: InputToken(address(tokenIn), inputAmount, inputAmount),
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
        emit Fill(orderHash, address(this), swapper, order.info.nonce);
        reactor.execute(signedOrder, address(fillContract), bytes(""));

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
        reactor.execute(signedOrder, address(fillContract), bytes(""));
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
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(swapper).withDeadline(block.timestamp + 100).withNonce(
                123
                ),
            input: InputToken(address(tokenIn), inputAmount, inputAmount),
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
        emit Fill(orderHash, address(this), swapper, order.info.nonce);
        reactor.execute(signedOrder, address(fillContract), bytes(""));

        assertEq(tokenIn.balanceOf(address(swapper)), swapperInputBalanceStart - inputAmount);
        assertEq(tokenIn.balanceOf(address(fillContract)), fillContractInputBalanceStart + inputAmount);
        assertEq(tokenOut.balanceOf(address(swapper)), swapperOutputBalanceStart + outputAmount);
        assertEq(tokenOut.balanceOf(address(fillContract)), fillContractOutputBalanceStart - outputAmount);

        // change deadline so sig and orderhash is different but nonce is the same
        order.info.deadline = block.timestamp + 101;
        (signedOrder, orderHash) = createAndSignOrder(order);
        vm.expectRevert(InvalidNonce.selector);
        reactor.execute(signedOrder, address(fillContract), bytes(""));
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
