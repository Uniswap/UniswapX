// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {Test} from "forge-std/Test.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {DeployPermit2} from "../util/DeployPermit2.sol";
import {
    DutchLimitOrderReactor,
    DutchLimitOrder,
    DutchInput,
    DutchOutput
} from "../../src/reactors/DutchLimitOrderReactor.sol";
import {OrderInfo, SignedOrder, ETH_ADDRESS} from "../../src/base/ReactorStructs.sol";
import {IPSFees} from "../../src/base/IPSFees.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {DutchLimitOrder, DutchLimitOrderLib} from "../../src/lib/DutchLimitOrderLib.sol";
import {BaseReactor} from "../../src/reactors/BaseReactor.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {CurrencyLibrary} from "../../src/lib/CurrencyLibrary.sol";

// This suite of tests test the direct taker fill macro, ie fillContract == address(1). It also contains tests
// for ETH outputs with direct taker.
contract DirectTakerFillMacroTest is Test, PermitSignature, GasSnapshot, DeployPermit2 {
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
    uint256 makerPrivateKey1;
    address maker1;
    uint256 makerPrivateKey2;
    address maker2;
    address directTaker;
    DutchLimitOrderReactor reactor;
    IAllowanceTransfer permit2;

    function setUp() public {
        tokenIn1 = new MockERC20("tokenIn1", "IN1", 18);
        tokenIn2 = new MockERC20("tokenIn2", "IN2", 18);
        tokenIn3 = new MockERC20("tokenIn3", "IN3", 18);
        tokenOut1 = new MockERC20("tokenOut1", "OUT1", 18);
        tokenOut2 = new MockERC20("tokenOut2", "OUT2", 18);
        tokenOut3 = new MockERC20("tokenOut3", "OUT3", 18);
        makerPrivateKey1 = 0x12341234;
        maker1 = vm.addr(makerPrivateKey1);
        makerPrivateKey2 = 0x12341235;
        maker2 = vm.addr(makerPrivateKey2);
        directTaker = address(888);
        permit2 = IAllowanceTransfer(deployPermit2());
        reactor = new DutchLimitOrderReactor(address(permit2), PROTOCOL_FEE_BPS, PROTOCOL_FEE_RECIPIENT);
        tokenIn1.forceApprove(maker1, address(permit2), type(uint256).max);
        tokenIn1.forceApprove(maker2, address(permit2), type(uint256).max);
        tokenIn2.forceApprove(maker2, address(permit2), type(uint256).max);
        tokenIn3.forceApprove(maker2, address(permit2), type(uint256).max);
        tokenOut1.forceApprove(directTaker, address(permit2), type(uint256).max);
        tokenOut2.forceApprove(directTaker, address(permit2), type(uint256).max);
        tokenOut3.forceApprove(directTaker, address(permit2), type(uint256).max);
        vm.prank(directTaker);
        permit2.approve(address(tokenOut1), address(reactor), type(uint160).max, type(uint48).max);
        vm.prank(directTaker);
        permit2.approve(address(tokenOut2), address(reactor), type(uint160).max, type(uint48).max);
        vm.prank(directTaker);
        permit2.approve(address(tokenOut3), address(reactor), type(uint160).max, type(uint48).max);
    }

    // Execute a single order made by maker1, input = 1 tokenIn1 and outputs = [2 tokenOut1].
    function testSingleOrder() public {
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn1.mint(address(maker1), inputAmount);
        tokenOut1.mint(directTaker, outputAmount);

        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker1).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut1), outputAmount, outputAmount, maker1)
        });

        vm.prank(directTaker);
        snapStart("DirectTakerFillMacroSingleOrder");
        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey1, address(permit2), order)), address(1), bytes("")
        );
        snapEnd();
        assertEq(tokenOut1.balanceOf(maker1), outputAmount);
        assertEq(tokenIn1.balanceOf(directTaker), inputAmount);
    }

    // The same as testSingleOrder, but with a 10% fee.
    function testSingleOrderWithFee() public {
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn1.mint(address(maker1), inputAmount);
        tokenOut1.mint(directTaker, outputAmount);

        DutchOutput[] memory dutchOutputs = new DutchOutput[](2);
        dutchOutputs[0] = DutchOutput(address(tokenOut1), outputAmount * 9 / 10, outputAmount * 9 / 10, maker1, false);
        dutchOutputs[1] = DutchOutput(address(tokenOut1), outputAmount / 10, outputAmount / 10, maker1, true);
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker1).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), inputAmount, inputAmount),
            outputs: dutchOutputs
        });

        vm.prank(directTaker);
        snapStart("DirectTakerFillMacroSingleOrderWithFee");
        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey1, address(permit2), order)), address(1), bytes("")
        );
        snapEnd();
        assertEq(tokenOut1.balanceOf(maker1), outputAmount * 9 / 10);
        assertEq(tokenOut1.balanceOf(address(reactor)), outputAmount / 10);
        assertEq(tokenIn1.balanceOf(directTaker), inputAmount);
    }

    // Execute two orders.
    // 1st order by maker1, input = 1 tokenIn1 and outputs = [2 tokenOut1]
    // 2nd order by maker2, input = 3 tokenIn2 and outputs = [1 tokenOut1, 3 tokenOut2]
    function testTwoOrders() public {
        tokenIn1.mint(address(maker1), ONE);
        tokenIn2.mint(address(maker2), ONE * 3);
        tokenOut1.mint(directTaker, ONE * 3);
        tokenOut2.mint(directTaker, ONE * 3);

        DutchLimitOrder memory order1 = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker1).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), ONE, ONE),
            outputs: OutputsBuilder.singleDutch(address(tokenOut1), ONE * 2, ONE * 2, maker1)
        });
        DutchOutput[] memory order2Outputs = new DutchOutput[](2);
        order2Outputs[0] = DutchOutput(address(tokenOut1), ONE, ONE, maker2, false);
        order2Outputs[1] = DutchOutput(address(tokenOut2), ONE * 3, ONE * 3, maker2, false);
        DutchLimitOrder memory order2 = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker2).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn2), ONE * 3, ONE * 3),
            outputs: order2Outputs
        });

        SignedOrder[] memory signedOrders = new SignedOrder[](2);
        signedOrders[0] = SignedOrder(abi.encode(order1), signOrder(makerPrivateKey1, address(permit2), order1));
        signedOrders[1] = SignedOrder(abi.encode(order2), signOrder(makerPrivateKey2, address(permit2), order2));
        vm.prank(directTaker);
        snapStart("DirectTakerFillMacroTwoOrders");
        reactor.executeBatch(signedOrders, address(1), bytes(""));
        snapEnd();

        assertEq(tokenOut1.balanceOf(maker1), 2 * ONE);
        assertEq(tokenOut1.balanceOf(maker2), ONE);
        assertEq(tokenOut2.balanceOf(maker2), 3 * ONE);
        assertEq(tokenIn1.balanceOf(directTaker), ONE);
        assertEq(tokenIn2.balanceOf(directTaker), 3 * ONE);
    }

    // Execute 3 orders, all with 10% fees
    // 1st order by maker1, input = 1 tokenIn1 and outputs = [1 tokenOut1]
    // 2nd order by maker2, input = 2 tokenIn2 and outputs = [2 tokenOut2]
    // 2nd order by maker2, input = 3 tokenIn3 and outputs = [3 tokenOut3]
    function testThreeOrdersWithFees() public {
        tokenIn1.mint(address(maker1), ONE);
        tokenIn2.mint(address(maker2), ONE * 2);
        tokenIn3.mint(address(maker2), ONE * 3);
        tokenOut1.mint(directTaker, ONE);
        tokenOut2.mint(directTaker, ONE * 2);
        tokenOut3.mint(directTaker, ONE * 3);

        DutchOutput[] memory dutchOutputs1 = new DutchOutput[](2);
        dutchOutputs1[0] = DutchOutput(address(tokenOut1), ONE * 9 / 10, ONE * 9 / 10, maker1, false);
        dutchOutputs1[1] = DutchOutput(address(tokenOut1), ONE / 10, ONE / 10, maker1, true);
        DutchLimitOrder memory order1 = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker1).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), ONE, ONE),
            outputs: dutchOutputs1
        });

        DutchOutput[] memory dutchOutputs2 = new DutchOutput[](2);
        dutchOutputs2[0] = DutchOutput(address(tokenOut2), ONE * 2 * 9 / 10, ONE * 2 * 9 / 10, maker2, false);
        dutchOutputs2[1] = DutchOutput(address(tokenOut2), ONE * 2 / 10, ONE * 2 / 10, maker2, true);
        DutchLimitOrder memory order2 = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker2).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn2), ONE * 2, ONE * 2),
            outputs: dutchOutputs2
        });

        DutchOutput[] memory dutchOutputs3 = new DutchOutput[](2);
        dutchOutputs3[0] = DutchOutput(address(tokenOut3), ONE * 3 * 9 / 10, ONE * 3 * 9 / 10, maker2, false);
        dutchOutputs3[1] = DutchOutput(address(tokenOut3), ONE * 3 / 10, ONE * 3 / 10, maker2, true);
        DutchLimitOrder memory order3 = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker2).withDeadline(block.timestamp + 100).withNonce(
                1
                ),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn3), ONE * 3, ONE * 3),
            outputs: dutchOutputs3
        });

        SignedOrder[] memory signedOrders = new SignedOrder[](3);
        signedOrders[0] = SignedOrder(abi.encode(order1), signOrder(makerPrivateKey1, address(permit2), order1));
        signedOrders[1] = SignedOrder(abi.encode(order2), signOrder(makerPrivateKey2, address(permit2), order2));
        signedOrders[2] = SignedOrder(abi.encode(order3), signOrder(makerPrivateKey2, address(permit2), order3));
        vm.prank(directTaker);
        snapStart("DirectTakerFillMacroThreeOrdersWithFees");
        reactor.executeBatch(signedOrders, address(1), bytes(""));
        snapEnd();

        assertEq(tokenOut1.balanceOf(maker1), ONE * 9 / 10);
        assertEq(tokenOut1.balanceOf(address(reactor)), ONE / 10);
        assertEq(tokenOut2.balanceOf(maker2), ONE * 2 * 9 / 10);
        assertEq(tokenOut2.balanceOf(address(reactor)), ONE * 2 / 10);
        assertEq(tokenOut3.balanceOf(maker2), ONE * 3 * 9 / 10);
        assertEq(tokenOut3.balanceOf(address(reactor)), ONE * 3 / 10);

        assertEq(tokenIn1.balanceOf(directTaker), ONE);
        assertEq(tokenIn2.balanceOf(directTaker), 2 * ONE);
        assertEq(tokenIn3.balanceOf(directTaker), 3 * ONE);
    }

    // Same test as `testSingleOrder`, but mint filler insufficient output
    function testFillerHasInsufficientOutput() public {
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn1.mint(address(maker1), inputAmount);
        tokenOut1.mint(directTaker, outputAmount - 1);

        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker1).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut1), outputAmount, outputAmount, maker1)
        });

        vm.prank(directTaker);
        vm.expectRevert(bytes("TRANSFER_FROM_FAILED"));
        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey1, address(permit2), order)), address(1), bytes("")
        );
    }

    // Same test as `testSingleOrder`, but filler lacks approval for tokenOut1
    function testFillerLacksApproval() public {
        vm.prank(directTaker);
        permit2.approve(address(tokenOut1), address(reactor), 0, type(uint48).max);

        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn1.mint(address(maker1), inputAmount);
        tokenOut1.mint(directTaker, outputAmount);

        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker1).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut1), outputAmount, outputAmount, maker1)
        });

        vm.prank(directTaker);
        vm.expectRevert(abi.encodeWithSignature("InsufficientAllowance(uint256)", 0));
        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey1, address(permit2), order)), address(1), bytes("")
        );
    }

    // Fill 1 order with requested output = 2 ETH.
    function testEth1Output() public {
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn1.mint(address(maker1), inputAmount);
        vm.deal(directTaker, outputAmount);

        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker1).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(ETH_ADDRESS, outputAmount, outputAmount, maker1)
        });

        vm.prank(directTaker);
        snapStart("DirectTakerFillMacroTestEth1Output");
        reactor.execute{value: outputAmount}(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey1, address(permit2), order)), address(1), bytes("")
        );
        snapEnd();
        assertEq(tokenIn1.balanceOf(directTaker), inputAmount);
        assertEq(maker1.balance, outputAmount);
    }

    // The same as testEth1Output, but reverts because directTaker doesn't send enough ether
    function testEth1OutputInsufficientEthSent() public {
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn1.mint(address(maker1), inputAmount);
        vm.deal(directTaker, outputAmount);

        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker1).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(ETH_ADDRESS, outputAmount, outputAmount, maker1)
        });

        vm.prank(directTaker);
        vm.expectRevert(CurrencyLibrary.NativeTransferFailed.selector);
        reactor.execute{value: outputAmount - 1}(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey1, address(permit2), order)), address(1), bytes("")
        );
    }

    // Fill 2 orders, both from `maker1`, one with output = 1 ETH and another with output = 2 ETH.
    function testEth2Outputs() public {
        uint256 inputAmount = 10 ** 18;

        tokenIn1.mint(address(maker1), inputAmount * 2);
        vm.deal(directTaker, ONE * 3);

        DutchLimitOrder memory order1 = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker1).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(ETH_ADDRESS, ONE, ONE, maker1)
        });
        DutchLimitOrder memory order2 = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker1).withDeadline(block.timestamp + 100).withNonce(
                1
                ),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(ETH_ADDRESS, ONE * 2, ONE * 2, maker1)
        });
        SignedOrder[] memory signedOrders = new SignedOrder[](2);
        signedOrders[0] = SignedOrder(abi.encode(order1), signOrder(makerPrivateKey1, address(permit2), order1));
        signedOrders[1] = SignedOrder(abi.encode(order2), signOrder(makerPrivateKey1, address(permit2), order2));

        vm.prank(directTaker);
        snapStart("DirectTakerFillMacroTestEth2Outputs");
        reactor.executeBatch{value: ONE * 3}(signedOrders, address(1), bytes(""));
        snapEnd();
        assertEq(tokenIn1.balanceOf(directTaker), 2 * inputAmount);
        assertEq(maker1.balance, 3 * ONE);
    }

    // The same setup as testEth2Outputs, but filler sends insufficient eth. However, there was already ETH in
    // the reactor to cover the difference, so the revert we expect is `InsufficientEth` instead of `EtherSendFail`.
    function testEth2OutputsInsufficientEthSentButEthInReactor() public {
        uint256 inputAmount = 10 ** 18;

        tokenIn1.mint(address(maker1), inputAmount * 2);
        vm.deal(directTaker, ONE * 3);
        vm.deal(address(reactor), ONE);

        DutchLimitOrder memory order1 = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker1).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(ETH_ADDRESS, ONE, ONE, maker1)
        });
        DutchLimitOrder memory order2 = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker1).withDeadline(block.timestamp + 100).withNonce(
                1
                ),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(ETH_ADDRESS, ONE * 2, ONE * 2, maker1)
        });
        SignedOrder[] memory signedOrders = new SignedOrder[](2);
        signedOrders[0] = SignedOrder(abi.encode(order1), signOrder(makerPrivateKey1, address(permit2), order1));
        signedOrders[1] = SignedOrder(abi.encode(order2), signOrder(makerPrivateKey1, address(permit2), order2));

        vm.prank(directTaker);
        vm.expectRevert(BaseReactor.InsufficientEth.selector);
        reactor.executeBatch{value: ONE * 3 - 1}(signedOrders, address(1), bytes(""));
    }

    // Fill 2 orders, with ETH and ERC20 outputs:
    // 1st order: from maker1, input = 1 tokenIn1, output = 1 tokenOut1
    // 2nd order: from maker2, input = 1 tokenIn1, output = [1 ETH, 0.05 ETH (fee)]
    function testEthOutputMixedOutputsAndFees() public {
        tokenIn1.mint(address(maker1), ONE);
        tokenIn1.mint(address(maker2), ONE);
        tokenOut1.mint(address(directTaker), ONE);
        vm.deal(directTaker, 2 * ONE);

        DutchLimitOrder memory order1 = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker1).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), ONE, ONE),
            outputs: OutputsBuilder.singleDutch(address(tokenOut1), ONE, ONE, maker1)
        });
        DutchOutput[] memory order2DutchOutputs = new DutchOutput[](2);
        order2DutchOutputs[0] = DutchOutput(ETH_ADDRESS, ONE, ONE, maker2, false);
        order2DutchOutputs[1] = DutchOutput(ETH_ADDRESS, ONE / 20, ONE / 20, maker2, true);
        DutchLimitOrder memory order2 = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker2).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), ONE, ONE),
            outputs: order2DutchOutputs
        });
        SignedOrder[] memory signedOrders = new SignedOrder[](2);
        signedOrders[0] = SignedOrder(abi.encode(order1), signOrder(makerPrivateKey1, address(permit2), order1));
        signedOrders[1] = SignedOrder(abi.encode(order2), signOrder(makerPrivateKey2, address(permit2), order2));

        vm.prank(directTaker);
        snapStart("DirectTakerFillMacroTestEthOutputMixedOutputsAndFees");
        reactor.executeBatch{value: ONE * 21 / 20}(signedOrders, address(1), bytes(""));
        snapEnd();
        assertEq(tokenIn1.balanceOf(directTaker), 2 * ONE);
        assertEq(maker2.balance, ONE);
        assertEq(address(reactor).balance, ONE / 20);
        assertEq(tokenOut1.balanceOf(maker1), ONE);
        assertEq(directTaker.balance, ONE * 19 / 20);
        assertEq(IPSFees(reactor).feesOwed(ETH_ADDRESS, maker2), 25000000000000000);
    }
}
