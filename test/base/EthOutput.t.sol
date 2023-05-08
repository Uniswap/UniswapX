// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {DeployPermit2} from "../util/DeployPermit2.sol";
import {OrderInfo, SignedOrder} from "../../src/base/ReactorStructs.sol";
import {CurrencyLibrary, NATIVE} from "../../src/lib/CurrencyLibrary.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {MockFillContract} from "../util/mock/MockFillContract.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {
    DutchLimitOrderReactor,
    DutchLimitOrder,
    DutchInput,
    DutchOutput
} from "../../src/reactors/DutchLimitOrderReactor.sol";
import {IPSFees} from "../../src/base/IPSFees.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {BaseReactor} from "../../src/reactors/BaseReactor.sol";
import {ExpectedBalanceLib} from "../../src/lib/ExpectedBalanceLib.sol";
import {DutchLimitOrderLib} from "../../src/lib/DutchLimitOrderLib.sol";

// This contract will test ETH outputs using DutchLimitOrderReactor as the reactor and MockFillContract for fillContract.
// Note that this contract only tests ETH outputs when NOT using direct filler.
contract EthOutputMockFillContractTest is Test, DeployPermit2, PermitSignature, GasSnapshot {
    using OrderInfoBuilder for OrderInfo;

    address constant PROTOCOL_FEE_RECIPIENT = address(2);
    uint256 constant PROTOCOL_FEE_BPS = 5000;
    uint256 constant ONE = 10 ** 18;

    MockERC20 tokenIn1;
    MockERC20 tokenOut1;
    uint256 swapperPrivateKey1;
    address swapper1;
    uint256 swapperPrivateKey2;
    address swapper2;
    DutchLimitOrderReactor reactor;
    IAllowanceTransfer permit2;
    MockFillContract fillContract;

    function setUp() public {
        tokenIn1 = new MockERC20("tokenIn1", "IN1", 18);
        tokenOut1 = new MockERC20("tokenOut1", "OUT1", 18);
        fillContract = new MockFillContract();
        swapperPrivateKey1 = 0x12341234;
        swapper1 = vm.addr(swapperPrivateKey1);
        swapperPrivateKey2 = 0x12341235;
        swapper2 = vm.addr(swapperPrivateKey2);
        permit2 = IAllowanceTransfer(deployPermit2());
        reactor = new DutchLimitOrderReactor(address(permit2), PROTOCOL_FEE_BPS, PROTOCOL_FEE_RECIPIENT);
        tokenIn1.forceApprove(swapper1, address(permit2), type(uint256).max);
        tokenIn1.forceApprove(swapper2, address(permit2), type(uint256).max);
    }

    // Fill one order (from swapper1, input = 1 tokenIn, output = 0.5 ETH (starts at 1 but decays to 0.5))
    function testEthOutput() public {
        tokenIn1.mint(address(swapper1), ONE);
        vm.deal(address(fillContract), ONE);

        vm.warp(1000);
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(swapper1).withDeadline(block.timestamp + 100),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), ONE, ONE),
            outputs: OutputsBuilder.singleDutch(NATIVE, ONE, 0, swapper1)
        });
        snapStart("EthOutputTestEthOutput");
        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey1, address(permit2), order)),
            address(fillContract),
            bytes("")
        );
        snapEnd();
        assertEq(tokenIn1.balanceOf(address(fillContract)), ONE);
        // There is 0.5 ETH remaining in the fillContract as output has decayed to 0.5 ETH
        assertEq(address(fillContract).balance, ONE / 2);
        assertEq(address(swapper1).balance, ONE / 2);
    }

    // Fill 3 orders
    // order 1: by swapper1, input = 1 tokenIn1, output = [2 ETH, 3 tokenOut1]
    // order 2: by swapper2, input = 2 tokenIn1, output = [3 ETH]
    // order 3: by swapper2, input = 3 tokenIn1, output = [4 tokenOut1]
    function test3OrdersWithEthAndERC20Outputs() public {
        tokenIn1.mint(address(swapper1), ONE);
        tokenIn1.mint(address(swapper2), ONE * 5);
        tokenOut1.mint(address(fillContract), ONE * 7);
        vm.deal(address(fillContract), ONE * 5);

        DutchOutput[] memory dutchOutputs = new DutchOutput[](2);
        dutchOutputs[0] = DutchOutput(NATIVE, 2 * ONE, 2 * ONE, swapper1, false);
        dutchOutputs[1] = DutchOutput(address(tokenOut1), 3 * ONE, 3 * ONE, swapper1, false);
        DutchLimitOrder memory order1 = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(swapper1).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), ONE, ONE),
            outputs: dutchOutputs
        });
        DutchLimitOrder memory order2 = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(swapper2).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), 2 * ONE, 2 * ONE),
            outputs: OutputsBuilder.singleDutch(NATIVE, 3 * ONE, 3 * ONE, swapper2)
        });
        DutchLimitOrder memory order3 = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(swapper2).withDeadline(block.timestamp + 100)
                .withNonce(1),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), 3 * ONE, 3 * ONE),
            outputs: OutputsBuilder.singleDutch(address(tokenOut1), 4 * ONE, 4 * ONE, swapper2)
        });

        SignedOrder[] memory signedOrders = new SignedOrder[](3);
        signedOrders[0] = SignedOrder(abi.encode(order1), signOrder(swapperPrivateKey1, address(permit2), order1));
        signedOrders[1] = SignedOrder(abi.encode(order2), signOrder(swapperPrivateKey2, address(permit2), order2));
        signedOrders[2] = SignedOrder(abi.encode(order3), signOrder(swapperPrivateKey2, address(permit2), order3));
        snapStart("EthOutputTest3OrdersWithEthAndERC20Outputs");
        reactor.executeBatch(signedOrders, address(fillContract), bytes(""));
        snapEnd();
        assertEq(tokenOut1.balanceOf(swapper1), 3 * ONE);
        assertEq(swapper1.balance, 2 * ONE);
        assertEq(swapper2.balance, 3 * ONE);
        assertEq(tokenOut1.balanceOf(swapper2), 4 * ONE);
        assertEq(tokenIn1.balanceOf(address(fillContract)), 6 * ONE);
        assertEq(address(fillContract).balance, 0);
    }

    // Same as `test3OrdersWithEthAndERC20Outputs` but the fillContract does not have enough ETH. The reactor does
    // not have enough ETH to cover the remainder, so we will revert with `NativeTransferFailed()`.
    function test3OrdersWithEthAndERC20OutputsWithInsufficientEth() public {
        tokenIn1.mint(address(swapper1), ONE);
        tokenIn1.mint(address(swapper2), ONE * 5);
        tokenOut1.mint(address(fillContract), ONE * 7);
        // Give fillContract only 4 ETH, when it requires 5
        vm.deal(address(fillContract), ONE * 4);

        DutchOutput[] memory dutchOutputs = new DutchOutput[](2);
        dutchOutputs[0] = DutchOutput(NATIVE, 2 * ONE, 2 * ONE, swapper1, false);
        dutchOutputs[1] = DutchOutput(address(tokenOut1), 3 * ONE, 3 * ONE, swapper1, false);
        DutchLimitOrder memory order1 = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(swapper1).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), ONE, ONE),
            outputs: dutchOutputs
        });
        DutchLimitOrder memory order2 = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(swapper2).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), 2 * ONE, 2 * ONE),
            outputs: OutputsBuilder.singleDutch(NATIVE, 3 * ONE, 3 * ONE, swapper2)
        });
        DutchLimitOrder memory order3 = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(swapper2).withDeadline(block.timestamp + 100)
                .withNonce(1),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), 3 * ONE, 3 * ONE),
            outputs: OutputsBuilder.singleDutch(address(tokenOut1), 4 * ONE, 4 * ONE, swapper2)
        });

        SignedOrder[] memory signedOrders = new SignedOrder[](3);
        signedOrders[0] = SignedOrder(abi.encode(order1), signOrder(swapperPrivateKey1, address(permit2), order1));
        signedOrders[1] = SignedOrder(abi.encode(order2), signOrder(swapperPrivateKey2, address(permit2), order2));
        signedOrders[2] = SignedOrder(abi.encode(order3), signOrder(swapperPrivateKey2, address(permit2), order3));
        vm.expectRevert(CurrencyLibrary.NativeTransferFailed.selector);
        reactor.executeBatch(signedOrders, address(fillContract), bytes(""));
    }

    // Same as `test3OrdersWithEthAndERC20Outputs` but the fillContract does not have enough ETH. The reactor DOES
    // have enough ETH to cover the remainder, so we will revert with `EtherSendFail()`.
    function test3OrdersWithEthAndERC20OutputsWithInsufficientEthInFillContractButEnoughInReactor() public {
        tokenIn1.mint(address(swapper1), ONE);
        tokenIn1.mint(address(swapper2), ONE * 5);
        tokenOut1.mint(address(fillContract), ONE * 7);
        // Give fillContract only 4 ETH, when it requires 5
        vm.deal(address(fillContract), ONE * 4);
        vm.deal(address(reactor), ONE * 100);

        DutchOutput[] memory dutchOutputs = new DutchOutput[](2);
        dutchOutputs[0] = DutchOutput(NATIVE, 2 * ONE, 2 * ONE, swapper1, false);
        dutchOutputs[1] = DutchOutput(address(tokenOut1), 3 * ONE, 3 * ONE, swapper1, false);
        DutchLimitOrder memory order1 = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(swapper1).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), ONE, ONE),
            outputs: dutchOutputs
        });
        DutchLimitOrder memory order2 = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(swapper2).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), 2 * ONE, 2 * ONE),
            outputs: OutputsBuilder.singleDutch(NATIVE, 3 * ONE, 3 * ONE, swapper2)
        });
        DutchLimitOrder memory order3 = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(swapper2).withDeadline(block.timestamp + 100)
                .withNonce(1),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), 3 * ONE, 3 * ONE),
            outputs: OutputsBuilder.singleDutch(address(tokenOut1), 4 * ONE, 4 * ONE, swapper2)
        });

        SignedOrder[] memory signedOrders = new SignedOrder[](3);
        signedOrders[0] = SignedOrder(abi.encode(order1), signOrder(swapperPrivateKey1, address(permit2), order1));
        signedOrders[1] = SignedOrder(abi.encode(order2), signOrder(swapperPrivateKey2, address(permit2), order2));
        signedOrders[2] = SignedOrder(abi.encode(order3), signOrder(swapperPrivateKey2, address(permit2), order3));
        vm.expectRevert(CurrencyLibrary.NativeTransferFailed.selector);
        reactor.executeBatch(signedOrders, address(fillContract), bytes(""));
    }
}

// This contract will test ETH outputs using DutchLimitOrderReactor as the reactor and direct filler.
contract EthOutputDirectFillerTest is Test, PermitSignature, GasSnapshot, DeployPermit2 {
    using OrderInfoBuilder for OrderInfo;
    using DutchLimitOrderLib for DutchLimitOrder;

    address constant PROTOCOL_FEE_RECIPIENT = address(2);
    uint256 constant PROTOCOL_FEE_BPS = 5000;
    uint256 constant ONE = 10 ** 18;

    MockERC20 tokenIn1;
    MockERC20 tokenIn2;
    MockERC20 tokenIn3;
    MockERC20 tokenOut1;
    MockERC20 tokenOut2;
    MockERC20 tokenOut3;
    uint256 swapperPrivateKey1;
    address swapper1;
    uint256 swapperPrivateKey2;
    address swapper2;
    address directFiller;
    DutchLimitOrderReactor reactor;
    IAllowanceTransfer permit2;

    function setUp() public {
        tokenIn1 = new MockERC20("tokenIn1", "IN1", 18);
        tokenIn2 = new MockERC20("tokenIn2", "IN2", 18);
        tokenIn3 = new MockERC20("tokenIn3", "IN3", 18);
        tokenOut1 = new MockERC20("tokenOut1", "OUT1", 18);
        tokenOut2 = new MockERC20("tokenOut2", "OUT2", 18);
        tokenOut3 = new MockERC20("tokenOut3", "OUT3", 18);
        swapperPrivateKey1 = 0x12341234;
        swapper1 = vm.addr(swapperPrivateKey1);
        swapperPrivateKey2 = 0x12341235;
        swapper2 = vm.addr(swapperPrivateKey2);
        directFiller = address(888);
        permit2 = IAllowanceTransfer(deployPermit2());
        reactor = new DutchLimitOrderReactor(address(permit2), PROTOCOL_FEE_BPS, PROTOCOL_FEE_RECIPIENT);
        tokenIn1.forceApprove(swapper1, address(permit2), type(uint256).max);
        tokenIn1.forceApprove(swapper2, address(permit2), type(uint256).max);
        tokenIn2.forceApprove(swapper2, address(permit2), type(uint256).max);
        tokenIn3.forceApprove(swapper2, address(permit2), type(uint256).max);
        tokenOut1.forceApprove(directFiller, address(permit2), type(uint256).max);
        tokenOut2.forceApprove(directFiller, address(permit2), type(uint256).max);
        tokenOut3.forceApprove(directFiller, address(permit2), type(uint256).max);
        vm.prank(directFiller);
        permit2.approve(address(tokenOut1), address(reactor), type(uint160).max, type(uint48).max);
        vm.prank(directFiller);
        permit2.approve(address(tokenOut2), address(reactor), type(uint160).max, type(uint48).max);
        vm.prank(directFiller);
        permit2.approve(address(tokenOut3), address(reactor), type(uint160).max, type(uint48).max);
    }

    // Fill 1 order with requested output = 2 ETH.
    function testEth1Output() public {
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn1.mint(address(swapper1), inputAmount);
        vm.deal(directFiller, outputAmount);

        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(swapper1).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(NATIVE, outputAmount, outputAmount, swapper1)
        });

        vm.prank(directFiller);
        snapStart("DirectFillerFillMacroTestEth1Output");
        reactor.execute{value: outputAmount}(
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey1, address(permit2), order)),
            address(1),
            bytes("")
        );
        snapEnd();
        assertEq(tokenIn1.balanceOf(directFiller), inputAmount);
        assertEq(swapper1.balance, outputAmount);
    }

    function testExcessETHIsReturned() public {
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn1.mint(address(swapper1), inputAmount);
        vm.deal(directFiller, outputAmount * 2);

        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(swapper1).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(NATIVE, outputAmount, outputAmount, swapper1)
        });

        vm.prank(directFiller);
        reactor.execute{value: outputAmount * 2}(
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey1, address(permit2), order)),
            address(1),
            bytes("")
        );
        // check directFiller received refund
        assertEq(directFiller.balance, outputAmount);
        assertEq(tokenIn1.balanceOf(directFiller), inputAmount);
        assertEq(swapper1.balance, outputAmount);
    }

    // The same as testEth1Output, but reverts because directFiller doesn't send enough ether
    function testEth1OutputInsufficientEthSent() public {
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn1.mint(address(swapper1), inputAmount);
        vm.deal(directFiller, outputAmount);

        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(swapper1).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(NATIVE, outputAmount, outputAmount, swapper1)
        });

        vm.prank(directFiller);
        vm.expectRevert(CurrencyLibrary.NativeTransferFailed.selector);
        reactor.execute{value: outputAmount - 1}(
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey1, address(permit2), order)),
            address(1),
            bytes("")
        );
    }

    // Fill 2 orders, both from `swapper1`, one with output = 1 ETH and another with output = 2 ETH.
    function testEth2Outputs() public {
        uint256 inputAmount = 10 ** 18;

        tokenIn1.mint(address(swapper1), inputAmount * 2);
        vm.deal(directFiller, ONE * 3);

        DutchLimitOrder memory order1 = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(swapper1).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(NATIVE, ONE, ONE, swapper1)
        });
        DutchLimitOrder memory order2 = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(swapper1).withDeadline(block.timestamp + 100)
                .withNonce(1),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(NATIVE, ONE * 2, ONE * 2, swapper1)
        });
        SignedOrder[] memory signedOrders = new SignedOrder[](2);
        signedOrders[0] = SignedOrder(abi.encode(order1), signOrder(swapperPrivateKey1, address(permit2), order1));
        signedOrders[1] = SignedOrder(abi.encode(order2), signOrder(swapperPrivateKey1, address(permit2), order2));

        vm.prank(directFiller);
        snapStart("DirectFillerFillMacroTestEth2Outputs");
        reactor.executeBatch{value: ONE * 3}(signedOrders, address(1), bytes(""));
        snapEnd();
        assertEq(tokenIn1.balanceOf(directFiller), 2 * inputAmount);
        assertEq(swapper1.balance, 3 * ONE);
    }

    // The same setup as testEth2Outputs, but filler sends insufficient eth. However, there was already ETH in
    // the reactor to cover the difference, so the revert we expect is `InsufficientEth` instead of `EtherSendFail`.
    function testEth2OutputsInsufficientEthSentButEthInReactor() public {
        uint256 inputAmount = 10 ** 18;

        tokenIn1.mint(address(swapper1), inputAmount * 2);
        vm.deal(directFiller, ONE * 3);
        vm.deal(address(reactor), ONE);

        DutchLimitOrder memory order1 = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(swapper1).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(NATIVE, ONE, ONE, swapper1)
        });
        DutchLimitOrder memory order2 = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(swapper1).withDeadline(block.timestamp + 100)
                .withNonce(1),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(NATIVE, ONE * 2, ONE * 2, swapper1)
        });
        SignedOrder[] memory signedOrders = new SignedOrder[](2);
        signedOrders[0] = SignedOrder(abi.encode(order1), signOrder(swapperPrivateKey1, address(permit2), order1));
        signedOrders[1] = SignedOrder(abi.encode(order2), signOrder(swapperPrivateKey1, address(permit2), order2));

        vm.prank(directFiller);
        vm.expectRevert(BaseReactor.InsufficientEth.selector);
        reactor.executeBatch{value: ONE * 3 - 1}(signedOrders, address(1), bytes(""));
    }

    // Fill 2 orders, with ETH and ERC20 outputs:
    // 1st order: from swapper1, input = 1 tokenIn1, output = 1 tokenOut1
    // 2nd order: from swapper2, input = 1 tokenIn1, output = [1 ETH, 0.05 ETH (fee)]
    function testEthOutputMixedOutputsAndFees() public {
        tokenIn1.mint(address(swapper1), ONE);
        tokenIn1.mint(address(swapper2), ONE);
        tokenOut1.mint(address(directFiller), ONE);
        vm.deal(directFiller, 2 * ONE);

        DutchLimitOrder memory order1 = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(swapper1).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), ONE, ONE),
            outputs: OutputsBuilder.singleDutch(address(tokenOut1), ONE, ONE, swapper1)
        });
        DutchOutput[] memory order2DutchOutputs = new DutchOutput[](2);
        order2DutchOutputs[0] = DutchOutput(NATIVE, ONE, ONE, swapper2, false);
        order2DutchOutputs[1] = DutchOutput(NATIVE, ONE / 20, ONE / 20, swapper2, true);
        DutchLimitOrder memory order2 = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(swapper2).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), ONE, ONE),
            outputs: order2DutchOutputs
        });
        SignedOrder[] memory signedOrders = new SignedOrder[](2);
        signedOrders[0] = SignedOrder(abi.encode(order1), signOrder(swapperPrivateKey1, address(permit2), order1));
        signedOrders[1] = SignedOrder(abi.encode(order2), signOrder(swapperPrivateKey2, address(permit2), order2));

        vm.prank(directFiller);
        snapStart("DirectFillerFillMacroTestEthOutputMixedOutputsAndFees");
        reactor.executeBatch{value: ONE * 21 / 20}(signedOrders, address(1), bytes(""));
        snapEnd();
        assertEq(tokenIn1.balanceOf(directFiller), 2 * ONE);
        assertEq(swapper2.balance, ONE);
        assertEq(address(reactor).balance, ONE / 20);
        assertEq(tokenOut1.balanceOf(swapper1), ONE);
        assertEq(directFiller.balance, ONE * 19 / 20);
        assertEq(IPSFees(reactor).feesOwed(NATIVE, swapper2), 25000000000000000);
    }
}
