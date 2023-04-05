// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.19;

import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {Test} from "forge-std/Test.sol";
import {BaseReactor} from "../../src/reactors/BaseReactor.sol";
import {ReactorEvents} from "../../src/base/ReactorEvents.sol";
import {SignedOrder, OrderInfo, InputToken, OutputToken} from "../../src/base/ReactorStructs.sol";
import {DeployPermit2} from "../util/DeployPermit2.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {ArrayBuilder} from "../util/ArrayBuilder.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {MockFillContract} from "../util/mock/MockFillContract.sol";

abstract contract BaseReactorTest is GasSnapshot, ReactorEvents, Test {
    using OrderInfoBuilder for OrderInfo;
    using ArrayBuilder for uint256[];
    using ArrayBuilder for uint256[][];

    uint256 constant ONE = 10 ** 18;

    MockERC20 tokenIn;
    MockERC20 tokenOut;
    MockFillContract fillContract;
    ISignatureTransfer permit2;
    BaseReactor reactor;
    uint256 makerPrivateKey;
    address maker;

    error InvalidNonce();
    error InvalidSigner();

    function name() public virtual returns (string memory) {}

    /// @dev Virtual function to set up the test and state variables
    function setUp() public virtual {}

    /// @dev Virtual function to create the specific reactor in state
    function createReactor() public virtual returns (BaseReactor) {}

    /// @dev Create a signed order and return the order and orderHash
    /// @param _info OrderInfo, uint256 inputAmount, uint256 outputAmount
    function createAndSignOrder(OrderInfo memory _info, uint256 inputAmount, uint256 outputAmount)
        public
        virtual
        returns (SignedOrder memory signedOrder, bytes32 orderHash)
    {}

    /// @dev Create many signed orders and return
    /// @param _infos OrderInfo[], uint256[] inputAmounts, uint256[][] outputAmounts
    /// supports orders with multiple outputs
    function createAndSignBatchOrders(
        OrderInfo[] memory _infos,
        uint256[] memory inputAmounts,
        uint256[][] memory outputAmounts
    ) public virtual returns (SignedOrder[] memory signedOrders, bytes32[] memory orderHashes) {}

    /// @dev Basic execute test, checks balance before and after
    function testBaseExecute() public {
        // Seed both maker and fillContract with enough tokens (important for dutch order)
        uint256 inputAmount = ONE;
        uint256 outputAmount = ONE * 2;
        tokenIn.mint(address(maker), inputAmount * 100);
        tokenOut.mint(address(fillContract), outputAmount * 100);
        tokenIn.forceApprove(maker, address(permit2), inputAmount);

        OrderInfo memory orderInfo =
            OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100);
        (SignedOrder memory signedOrder, bytes32 orderHash) = createAndSignOrder(orderInfo, inputAmount, outputAmount);

        (
            uint256 makerInputBalanceStart,
            uint256 fillContractInputBalanceStart,
            uint256 makerOutputBalanceStart,
            uint256 fillContractOutputBalanceStart
        ) = _checkpointBalances();

        // TODO: expand to allow for custom fillData in 3rd param
        vm.expectEmit(true, true, true, true, address(reactor));
        emit Fill(orderHash, address(this), maker, orderInfo.nonce);
        // execute order
        snapStart(string.concat(name(), "BaseExecuteSingle"));
        reactor.execute(signedOrder, address(fillContract), bytes(""));
        snapEnd();

        assertEq(tokenIn.balanceOf(address(maker)), makerInputBalanceStart - inputAmount);
        assertEq(tokenIn.balanceOf(address(fillContract)), fillContractInputBalanceStart + inputAmount);
        assertEq(tokenOut.balanceOf(address(maker)), makerOutputBalanceStart + outputAmount);
        assertEq(tokenOut.balanceOf(address(fillContract)), fillContractOutputBalanceStart - outputAmount);
    }

    /// @dev Basic batch execute test
    // Two orders: (inputs = 1, outputs = 2), (inputs = 2, outputs = 4)
    function testBaseExecuteBatch() public {
        uint256 inputAmount = ONE;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn.mint(address(maker), inputAmount * 3);
        tokenOut.mint(address(fillContract), 6 * 10 ** 18);
        tokenIn.forceApprove(maker, address(permit2), type(uint256).max);

        uint256[] memory inputAmounts = ArrayBuilder.fill(1, inputAmount).push(2 * inputAmount);
        uint256[][] memory outputAmounts = ArrayBuilder.init(2, 1).set(0, ArrayBuilder.fill(1, outputAmount)).set(
            1, ArrayBuilder.fill(1, 2 * outputAmount)
        );

        uint256 totalOutputAmount = outputAmounts.sum();
        uint256 totalInputAmount = inputAmounts.sum();

        OrderInfo[] memory infos = new OrderInfo[](2);
        infos[0] =
            OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100).withNonce(0);
        infos[1] =
            OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100).withNonce(1);

        (SignedOrder[] memory signedOrders, bytes32[] memory orderHashes) =
            createAndSignBatchOrders(infos, inputAmounts, outputAmounts);
        vm.expectEmit(true, true, true, true);
        emit Fill(orderHashes[0], address(this), maker, infos[0].nonce);
        vm.expectEmit(true, true, true, true);
        emit Fill(orderHashes[1], address(this), maker, infos[1].nonce);

        snapStart(string.concat(name(), "BaseExecuteBatch"));
        reactor.executeBatch(signedOrders, address(fillContract), bytes(""));
        snapEnd();

        assertEq(tokenOut.balanceOf(maker), totalOutputAmount);
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

        tokenIn.mint(address(maker), totalInputAmount);
        tokenOut.mint(address(fillContract), totalOutputAmount);
        tokenIn.forceApprove(maker, address(permit2), type(uint256).max);

        OrderInfo[] memory infos = new OrderInfo[](2);
        infos[0] =
            OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100).withNonce(0);
        infos[1] =
            OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100).withNonce(1);

        (SignedOrder[] memory signedOrders, bytes32[] memory orderHashes) =
            createAndSignBatchOrders(infos, inputAmounts, outputAmounts);
        vm.expectEmit(true, true, true, true);
        emit Fill(orderHashes[0], address(this), maker, infos[0].nonce);
        vm.expectEmit(true, true, true, true);
        emit Fill(orderHashes[1], address(this), maker, infos[1].nonce);

        snapStart(string.concat(name(), "BaseExecuteBatchMultipleOutputs"));
        reactor.executeBatch(signedOrders, address(fillContract), bytes(""));
        snapEnd();

        assertEq(tokenOut.balanceOf(maker), totalOutputAmount);
        assertEq(tokenIn.balanceOf(address(fillContract)), totalInputAmount);
    }

    /// @dev Base test preventing signatures from being reused
    function testBaseExecuteSignatureReplay() public {
        // Seed both maker and fillContract with enough tokens
        uint256 inputAmount = ONE;
        uint256 outputAmount = ONE * 2;
        tokenIn.mint(address(maker), inputAmount * 100);
        tokenOut.mint(address(fillContract), outputAmount * 100);
        tokenIn.forceApprove(maker, address(permit2), inputAmount);

        OrderInfo memory orderInfo =
            OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100);
        (SignedOrder memory signedOrder, bytes32 orderHash) = createAndSignOrder(orderInfo, inputAmount, outputAmount);

        (
            uint256 makerInputBalanceStart,
            uint256 fillContractInputBalanceStart,
            uint256 makerOutputBalanceStart,
            uint256 fillContractOutputBalanceStart
        ) = _checkpointBalances();

        vm.expectEmit(true, true, true, true, address(reactor));
        emit Fill(orderHash, address(this), maker, orderInfo.nonce);
        reactor.execute(signedOrder, address(fillContract), bytes(""));

        assertEq(tokenIn.balanceOf(address(maker)), makerInputBalanceStart - inputAmount);
        assertEq(tokenIn.balanceOf(address(fillContract)), fillContractInputBalanceStart + inputAmount);
        assertEq(tokenOut.balanceOf(address(maker)), makerOutputBalanceStart + outputAmount);
        assertEq(tokenOut.balanceOf(address(fillContract)), fillContractOutputBalanceStart - outputAmount);

        tokenIn.mint(address(maker), inputAmount);
        tokenOut.mint(address(fillContract), outputAmount);
        tokenIn.forceApprove(maker, address(permit2), inputAmount);

        bytes memory oldSignature = signedOrder.sig;
        // Create a new order, but use the previous signature
        (signedOrder, orderHash) = createAndSignOrder(
            OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100).withNonce(1),
            inputAmount,
            outputAmount
        );
        signedOrder.sig = oldSignature;

        vm.expectRevert(InvalidSigner.selector);
        reactor.execute(signedOrder, address(fillContract), bytes(""));
    }

    /// @dev Base test preventing nonce reuse
    function testBaseNonceReuse() public {
        uint256 inputAmount = ONE;
        uint256 outputAmount = ONE * 2;
        tokenIn.mint(address(maker), inputAmount * 100);
        tokenOut.mint(address(fillContract), outputAmount * 100);
        // approve for 2 orders here
        tokenIn.forceApprove(maker, address(permit2), inputAmount * 2);

        OrderInfo memory orderInfo = OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(
            block.timestamp + 100
        ).withNonce(123);
        (SignedOrder memory signedOrder, bytes32 orderHash) = createAndSignOrder(orderInfo, inputAmount, outputAmount);

        (
            uint256 makerInputBalanceStart,
            uint256 fillContractInputBalanceStart,
            uint256 makerOutputBalanceStart,
            uint256 fillContractOutputBalanceStart
        ) = _checkpointBalances();

        vm.expectEmit(true, true, true, true, address(reactor));
        emit Fill(orderHash, address(this), maker, orderInfo.nonce);
        reactor.execute(signedOrder, address(fillContract), bytes(""));

        assertEq(tokenIn.balanceOf(address(maker)), makerInputBalanceStart - inputAmount);
        assertEq(tokenIn.balanceOf(address(fillContract)), fillContractInputBalanceStart + inputAmount);
        assertEq(tokenOut.balanceOf(address(maker)), makerOutputBalanceStart + outputAmount);
        assertEq(tokenOut.balanceOf(address(fillContract)), fillContractOutputBalanceStart - outputAmount);

        orderInfo = OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100)
            .withNonce(123);
        (signedOrder, orderHash) = createAndSignOrder(orderInfo, inputAmount, outputAmount);
        vm.expectRevert(InvalidNonce.selector);
        reactor.execute(signedOrder, address(fillContract), bytes(""));
    }

    function _checkpointBalances()
        internal
        view
        returns (
            uint256 makerInputBalanceStart,
            uint256 fillContractInputBalanceStart,
            uint256 makerOutputBalanceStart,
            uint256 fillContractOutputBalanceStart
        )
    {
        makerInputBalanceStart = tokenIn.balanceOf(address(maker));
        fillContractInputBalanceStart = tokenIn.balanceOf(address(fillContract));
        makerOutputBalanceStart = tokenOut.balanceOf(address(maker));
        fillContractOutputBalanceStart = tokenOut.balanceOf(address(fillContract));
    }
}
