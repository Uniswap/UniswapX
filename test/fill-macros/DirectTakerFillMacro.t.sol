// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {Test} from "forge-std/Test.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {DeployPermit2} from "../util/DeployPermit2.sol";
import {DutchOrderReactor, DutchOrder, DutchInput, DutchOutput} from "../../src/reactors/DutchOrderReactor.sol";
import {OrderInfo, SignedOrder} from "../../src/base/ReactorStructs.sol";
import {NATIVE} from "../../src/lib/CurrencyLibrary.sol";
import {ProtocolFees} from "../../src/base/ProtocolFees.sol";
import {IReactorCallback} from "../../src/interfaces/IReactorCallback.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {DutchOrder, DutchOrderLib} from "../../src/lib/DutchOrderLib.sol";
import {BaseReactor} from "../../src/reactors/BaseReactor.sol";
import {MockFeeController} from "../util/mock/MockFeeController.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {CurrencyLibrary} from "../../src/lib/CurrencyLibrary.sol";

// This suite of tests test the direct filler fill macro, ie fillContract == address(1).
contract DirectFillerFillMacroTest is Test, PermitSignature, GasSnapshot, DeployPermit2 {
    using OrderInfoBuilder for OrderInfo;
    using DutchOrderLib for DutchOrder;

    address constant PROTOCOL_FEE_OWNER = address(2);
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
    DutchOrderReactor reactor;
    IPermit2 permit2;

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
        permit2 = IPermit2(deployPermit2());
        reactor = new DutchOrderReactor(permit2, PROTOCOL_FEE_OWNER);
        tokenIn1.forceApprove(swapper1, address(permit2), type(uint256).max);
        tokenIn1.forceApprove(swapper2, address(permit2), type(uint256).max);
        tokenIn2.forceApprove(swapper2, address(permit2), type(uint256).max);
        tokenIn3.forceApprove(swapper2, address(permit2), type(uint256).max);
        tokenOut1.forceApprove(directFiller, address(reactor), type(uint256).max);
        tokenOut2.forceApprove(directFiller, address(reactor), type(uint256).max);
        tokenOut3.forceApprove(directFiller, address(reactor), type(uint256).max);
    }

    // Execute a single order made by swapper1, input = 1 tokenIn1 and outputs = [2 tokenOut1].
    function testSingleOrder() public {
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn1.mint(address(swapper1), inputAmount);
        tokenOut1.mint(directFiller, outputAmount);

        DutchOrder memory order = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper1).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn1, inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut1), outputAmount, outputAmount, swapper1)
        });

        vm.prank(directFiller);
        snapStart("DirectFillerFillMacroSingleOrder");
        reactor.execute(SignedOrder(abi.encode(order), signOrder(swapperPrivateKey1, address(permit2), order)));
        snapEnd();
        assertEq(tokenOut1.balanceOf(swapper1), outputAmount);
        assertEq(tokenIn1.balanceOf(directFiller), inputAmount);
    }

    // Execute a single order made by swapper1, input = 1 tokenIn1 and outputs = [2 tokenOut1].
    function testFillDataPassed() public {
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn1.mint(address(swapper1), inputAmount);
        tokenOut1.mint(directFiller, outputAmount);

        DutchOrder memory order = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper1).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn1, inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut1), outputAmount, outputAmount, swapper1)
        });

        vm.prank(directFiller);
        // throws because attempting to call reactorCallback on an EOA
        // and solidity high level calls add a codesize check
        vm.expectRevert();
        reactor.executeWithCallback(
            SignedOrder(abi.encode(order), signOrder(swapperPrivateKey1, address(permit2), order)), hex""
        );
    }

    // The same as testSingleOrder, but with a 10% fee.
    function testSingleOrderWithFee() public {
        address feeRecipient = address(1);
        MockFeeController feeController = new MockFeeController(feeRecipient);
        vm.prank(PROTOCOL_FEE_OWNER);
        reactor.setProtocolFeeController(address(feeController));
        uint256 feeBps = 5;
        feeController.setFee(tokenIn1, address(tokenOut1), feeBps);

        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn1.mint(address(swapper1), inputAmount);
        tokenOut1.mint(directFiller, outputAmount * (10000 + feeBps) / 10000);

        DutchOutput[] memory dutchOutputs = new DutchOutput[](2);
        dutchOutputs[0] = DutchOutput(address(tokenOut1), outputAmount * 9 / 10, outputAmount * 9 / 10, swapper1);
        dutchOutputs[1] = DutchOutput(address(tokenOut1), outputAmount / 10, outputAmount / 10, swapper1);
        DutchOrder memory order = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper1).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn1, inputAmount, inputAmount),
            outputs: dutchOutputs
        });

        vm.prank(directFiller);
        snapStart("DirectFillerFillMacroSingleOrderWithFee");
        reactor.execute(SignedOrder(abi.encode(order), signOrder(swapperPrivateKey1, address(permit2), order)));
        snapEnd();
        assertEq(tokenOut1.balanceOf(swapper1), outputAmount);
        assertEq(tokenOut1.balanceOf(address(feeRecipient)), outputAmount * feeBps / 10000);
        assertEq(tokenIn1.balanceOf(directFiller), inputAmount);
    }

    // Execute two orders.
    // 1st order by swapper1, input = 1 tokenIn1 and outputs = [2 tokenOut1]
    // 2nd order by swapper2, input = 3 tokenIn2 and outputs = [1 tokenOut1, 3 tokenOut2]
    function testTwoOrders() public {
        tokenIn1.mint(address(swapper1), ONE);
        tokenIn2.mint(address(swapper2), ONE * 3);
        tokenOut1.mint(directFiller, ONE * 3);
        tokenOut2.mint(directFiller, ONE * 3);

        DutchOrder memory order1 = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper1).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn1, ONE, ONE),
            outputs: OutputsBuilder.singleDutch(address(tokenOut1), ONE * 2, ONE * 2, swapper1)
        });
        DutchOutput[] memory order2Outputs = new DutchOutput[](2);
        order2Outputs[0] = DutchOutput(address(tokenOut1), ONE, ONE, swapper2);
        order2Outputs[1] = DutchOutput(address(tokenOut2), ONE * 3, ONE * 3, swapper2);
        DutchOrder memory order2 = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper2).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn2, ONE * 3, ONE * 3),
            outputs: order2Outputs
        });

        SignedOrder[] memory signedOrders = new SignedOrder[](2);
        signedOrders[0] = SignedOrder(abi.encode(order1), signOrder(swapperPrivateKey1, address(permit2), order1));
        signedOrders[1] = SignedOrder(abi.encode(order2), signOrder(swapperPrivateKey2, address(permit2), order2));
        vm.prank(directFiller);
        snapStart("DirectFillerFillMacroTwoOrders");
        reactor.executeBatch(signedOrders);
        snapEnd();

        assertEq(tokenOut1.balanceOf(swapper1), 2 * ONE);
        assertEq(tokenOut1.balanceOf(swapper2), ONE);
        assertEq(tokenOut2.balanceOf(swapper2), 3 * ONE);
        assertEq(tokenIn1.balanceOf(directFiller), ONE);
        assertEq(tokenIn2.balanceOf(directFiller), 3 * ONE);
    }

    // Execute 3 orders, all with 10% fees
    // 1st order by swapper1, input = 1 tokenIn1 and outputs = [1 tokenOut1]
    // 2nd order by swapper2, input = 2 tokenIn2 and outputs = [2 tokenOut2]
    // 2nd order by swapper2, input = 3 tokenIn3 and outputs = [3 tokenOut3]
    function testThreeOrdersWithFees() public {
        address feeRecipient = address(1);
        MockFeeController feeController = new MockFeeController(feeRecipient);
        vm.prank(PROTOCOL_FEE_OWNER);
        reactor.setProtocolFeeController(address(feeController));
        uint256 feeBps = 5;
        feeController.setFee(tokenIn1, address(tokenOut1), feeBps);
        feeController.setFee(tokenIn2, address(tokenOut2), feeBps);
        feeController.setFee(tokenIn3, address(tokenOut3), feeBps);

        tokenIn1.mint(address(swapper1), ONE);
        tokenIn2.mint(address(swapper2), ONE * 2);
        tokenIn3.mint(address(swapper2), ONE * 3);
        tokenOut1.mint(directFiller, ONE * (10000 + feeBps) / 10000);
        tokenOut2.mint(directFiller, ONE * 2 * (10000 + feeBps) / 10000);
        tokenOut3.mint(directFiller, ONE * 3 * (10000 + feeBps) / 10000);

        DutchOutput[] memory dutchOutputs1 = new DutchOutput[](2);
        dutchOutputs1[0] = DutchOutput(address(tokenOut1), ONE * 9 / 10, ONE * 9 / 10, swapper1);
        dutchOutputs1[1] = DutchOutput(address(tokenOut1), ONE / 10, ONE / 10, swapper1);
        DutchOrder memory order1 = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper1).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn1, ONE, ONE),
            outputs: dutchOutputs1
        });

        DutchOutput[] memory dutchOutputs2 = new DutchOutput[](2);
        dutchOutputs2[0] = DutchOutput(address(tokenOut2), ONE * 2 * 9 / 10, ONE * 2 * 9 / 10, swapper2);
        dutchOutputs2[1] = DutchOutput(address(tokenOut2), ONE * 2 / 10, ONE * 2 / 10, swapper2);
        DutchOrder memory order2 = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper2).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn2, ONE * 2, ONE * 2),
            outputs: dutchOutputs2
        });

        DutchOutput[] memory dutchOutputs3 = new DutchOutput[](2);
        dutchOutputs3[0] = DutchOutput(address(tokenOut3), ONE * 3 * 9 / 10, ONE * 3 * 9 / 10, swapper2);
        dutchOutputs3[1] = DutchOutput(address(tokenOut3), ONE * 3 / 10, ONE * 3 / 10, swapper2);
        DutchOrder memory order3 = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper2).withDeadline(block.timestamp + 100)
                .withNonce(1),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn3, ONE * 3, ONE * 3),
            outputs: dutchOutputs3
        });

        SignedOrder[] memory signedOrders = new SignedOrder[](3);
        signedOrders[0] = SignedOrder(abi.encode(order1), signOrder(swapperPrivateKey1, address(permit2), order1));
        signedOrders[1] = SignedOrder(abi.encode(order2), signOrder(swapperPrivateKey2, address(permit2), order2));
        signedOrders[2] = SignedOrder(abi.encode(order3), signOrder(swapperPrivateKey2, address(permit2), order3));
        vm.prank(directFiller);
        snapStart("DirectFillerFillMacroThreeOrdersWithFees");
        reactor.executeBatch(signedOrders);
        snapEnd();

        assertEq(tokenOut1.balanceOf(swapper1), ONE);
        assertEq(tokenOut1.balanceOf(address(feeRecipient)), ONE * feeBps / 10000);
        assertEq(tokenOut2.balanceOf(swapper2), ONE * 2);
        assertEq(tokenOut2.balanceOf(address(feeRecipient)), ONE * 2 * feeBps / 10000);
        assertEq(tokenOut3.balanceOf(swapper2), ONE * 3);
        assertEq(tokenOut3.balanceOf(address(feeRecipient)), ONE * 3 * feeBps / 10000);

        assertEq(tokenIn1.balanceOf(directFiller), ONE);
        assertEq(tokenIn2.balanceOf(directFiller), 2 * ONE);
        assertEq(tokenIn3.balanceOf(directFiller), 3 * ONE);
    }

    // Same test as `testSingleOrder`, but mint filler insufficient output
    function testFillerHasInsufficientOutput() public {
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn1.mint(address(swapper1), inputAmount);
        tokenOut1.mint(directFiller, outputAmount - 1);

        DutchOrder memory order = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper1).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn1, inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut1), outputAmount, outputAmount, swapper1)
        });

        vm.prank(directFiller);
        vm.expectRevert(bytes("TRANSFER_FROM_FAILED"));
        reactor.execute(SignedOrder(abi.encode(order), signOrder(swapperPrivateKey1, address(permit2), order)));
    }

    // Same test as `testSingleOrder`, but filler lacks approval for tokenOut1
    function testFillerLacksApproval() public {
        vm.prank(directFiller);
        tokenOut1.approve(address(reactor), 0);

        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn1.mint(address(swapper1), inputAmount);
        tokenOut1.mint(directFiller, outputAmount);

        DutchOrder memory order = DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper1).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            input: DutchInput(tokenIn1, inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut1), outputAmount, outputAmount, swapper1)
        });

        vm.prank(directFiller);
        vm.expectRevert("TRANSFER_FROM_FAILED");
        reactor.execute(SignedOrder(abi.encode(order), signOrder(swapperPrivateKey1, address(permit2), order)));
    }
}
