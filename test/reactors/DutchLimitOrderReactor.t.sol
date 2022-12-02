// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {Test} from "forge-std/Test.sol";
import {Permit2} from "permit2/Permit2.sol";
import {
    DutchLimitOrderReactor,
    DutchLimitOrder,
    ResolvedOrder,
    DutchOutput,
    DutchInput
} from "../../src/reactors/DutchLimitOrderReactor.sol";
import {OrderInfo, InputToken, SignedOrder} from "../../src/base/ReactorStructs.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {MockDutchLimitOrderReactor} from "../util/mock/MockDutchLimitOrderReactor.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {DutchLimitOrder, DutchLimitOrderLib} from "../../src/lib/DutchLimitOrderLib.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {MockFillContract} from "../util/mock/MockFillContract.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {ReactorEvents} from "../../src/base/ReactorEvents.sol";

// This suite of tests test validation and resolves.
contract DutchLimitOrderReactorValidationTest is Test {
    using OrderInfoBuilder for OrderInfo;

    address constant PROTOCOL_FEE_RECIPIENT = address(1);
    uint256 constant PROTOCOL_FEE_BPS = 5000;

    MockDutchLimitOrderReactor reactor;
    Permit2 permit2;

    function setUp() public {
        permit2 = new Permit2();
        reactor = new MockDutchLimitOrderReactor(address(permit2), PROTOCOL_FEE_BPS, PROTOCOL_FEE_RECIPIENT);
    }

    // 1000 - (1000-900) * (1659087340-1659029740) / (1659130540-1659029740) = 943
    function testResolveEndTimeAfterNow() public {
        vm.warp(1659087340);
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(0), 1000, 900, address(0), false);
        DutchLimitOrder memory dlo = DutchLimitOrder(
            OrderInfoBuilder.init(address(reactor)).withDeadline(1659130540),
            1659029740,
            1659130540,
            DutchInput(address(0), 0, 0),
            dutchOutputs
        );
        bytes memory sig = hex"1234";
        ResolvedOrder memory resolvedOrder = reactor.resolveOrder(SignedOrder(abi.encode(dlo), sig));
        assertEq(resolvedOrder.outputs[0].amount, 943);
        assertEq(resolvedOrder.outputs.length, 1);
        assertEq(resolvedOrder.input.amount, 0);
        assertEq(resolvedOrder.input.token, address(0));
    }

    // Test multiple dutch outputs get resolved correctly. Use same time points as
    // testResolveEndTimeAfterNow().
    function testResolveMultipleDutchOutputs() public {
        vm.warp(1659087340);
        DutchOutput[] memory dutchOutputs = new DutchOutput[](3);
        dutchOutputs[0] = DutchOutput(address(0), 1000, 900, address(0), false);
        dutchOutputs[1] = DutchOutput(address(0), 10000, 9000, address(0), false);
        dutchOutputs[2] = DutchOutput(address(0), 2000, 1000, address(0), false);
        DutchLimitOrder memory dlo = DutchLimitOrder(
            OrderInfoBuilder.init(address(reactor)).withDeadline(1659130540),
            1659029740,
            1659130540,
            DutchInput(address(0), 0, 0),
            dutchOutputs
        );
        bytes memory sig = hex"1234";
        ResolvedOrder memory resolvedOrder = reactor.resolveOrder(SignedOrder(abi.encode(dlo), sig));
        assertEq(resolvedOrder.outputs.length, 3);
        assertEq(resolvedOrder.outputs[0].amount, 943);
        assertEq(resolvedOrder.outputs[1].amount, 9429);
        assertEq(resolvedOrder.outputs[2].amount, 1429);
        assertEq(resolvedOrder.input.amount, 0);
        assertEq(resolvedOrder.input.token, address(0));
    }

    // Test that when startTime = now, that the output = startAmount
    function testResolveStartTimeEqualsNow() public {
        vm.warp(1659029740);
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(0), 1000, 900, address(0), false);
        DutchLimitOrder memory dlo = DutchLimitOrder(
            OrderInfoBuilder.init(address(reactor)).withDeadline(1659130540),
            1659029740,
            1659130540,
            DutchInput(address(0), 0, 0),
            dutchOutputs
        );
        bytes memory sig = hex"1234";
        ResolvedOrder memory resolvedOrder = reactor.resolveOrder(SignedOrder(abi.encode(dlo), sig));
        assertEq(resolvedOrder.outputs[0].amount, 1000);
        assertEq(resolvedOrder.outputs.length, 1);
        assertEq(resolvedOrder.input.amount, 0);
        assertEq(resolvedOrder.input.token, address(0));
    }

    // startAmount is expected to always be greater than endAmount
    // otherwise the order decays out of favor for the offerer
    function testStartAmountLessThanEndAmount() public {
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(0), 900, 1000, address(0), false);
        DutchLimitOrder memory dlo = DutchLimitOrder(
            OrderInfoBuilder.init(address(reactor)).withDeadline(block.timestamp + 100),
            block.timestamp,
            block.timestamp + 100,
            DutchInput(address(0), 0, 0),
            dutchOutputs
        );
        vm.expectRevert(DutchLimitOrderReactor.IncorrectAmounts.selector);
        bytes memory sig = hex"1234";
        reactor.resolveOrder(SignedOrder(abi.encode(dlo), sig));
    }

    // At time 1659030747, output will still be 1000. One second later at 1659030748,
    // the first decay will occur and the output will be 999.
    function testResolveFirstDecay() public {
        vm.warp(1659030747);
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(0), 1000, 900, address(0), false);
        DutchLimitOrder memory dlo = DutchLimitOrder(
            OrderInfoBuilder.init(address(reactor)).withDeadline(1659130540),
            1659029740,
            1659130540,
            DutchInput(address(0), 0, 0),
            dutchOutputs
        );
        bytes memory sig = hex"1234";
        ResolvedOrder memory resolvedOrder = reactor.resolveOrder(SignedOrder(abi.encode(dlo), sig));
        assertEq(resolvedOrder.outputs[0].amount, 1000);

        vm.warp(1659030748);
        resolvedOrder = reactor.resolveOrder(SignedOrder(abi.encode(dlo), sig));
        assertEq(resolvedOrder.outputs[0].amount, 999);
    }

    function testValidateDutchEndTimeBeforeStart() public {
        vm.expectRevert(DutchLimitOrderReactor.EndTimeBeforeStartTime.selector);
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(0), 1000, 900, address(0), false);
        DutchLimitOrder memory dlo = DutchLimitOrder(
            OrderInfoBuilder.init(address(reactor)).withDeadline(1659130540),
            1659130541,
            1659130540,
            DutchInput(address(0), 0, 0),
            dutchOutputs
        );
        bytes memory sig = hex"1234";
        reactor.resolveOrder(SignedOrder(abi.encode(dlo), sig));
    }

    function testValidateDutchEndTimeAfterStart() public view {
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(0), 1000, 900, address(0), false);
        DutchLimitOrder memory dlo = DutchLimitOrder(
            OrderInfoBuilder.init(address(reactor)).withDeadline(1659130540),
            1659120540,
            1659130540,
            DutchInput(address(0), 0, 0),
            dutchOutputs
        );
        bytes memory sig = hex"1234";
        reactor.resolveOrder(SignedOrder(abi.encode(dlo), sig));
    }

    function testValidateEndTimeAfterDeadline() public {
        vm.expectRevert(DutchLimitOrderReactor.DeadlineBeforeEndTime.selector);
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(0), 1000, 900, address(0), false);
        DutchLimitOrder memory dlo = DutchLimitOrder(
            OrderInfoBuilder.init(address(reactor)).withDeadline(100),
            50,
            101,
            DutchInput(address(0), 0, 0),
            dutchOutputs
        );
        bytes memory sig = hex"1234";
        reactor.resolveOrder(SignedOrder(abi.encode(dlo), sig));
    }

    function testDecayNeverOutOfBounds(uint256 startTime, uint256 startAmount, uint256 endTime, uint256 endAmount)
        public
    {
        vm.assume(startTime < endTime);
        vm.assume(startAmount > endAmount);
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(0), startAmount, endAmount, address(0), false);
        DutchLimitOrder memory dlo = DutchLimitOrder(
            OrderInfoBuilder.init(address(reactor)).withDeadline(endTime),
            startTime,
            endTime,
            DutchInput(address(0), 0, 0),
            dutchOutputs
        );
        bytes memory sig = hex"1234";
        ResolvedOrder memory resolvedOrder = reactor.resolveOrder(SignedOrder(abi.encode(dlo), sig));
        assertLe(resolvedOrder.outputs[0].amount, startAmount);
        assertGe(resolvedOrder.outputs[0].amount, endAmount);
    }

    // The input decays, which means the outputs must not decay. In this test, the
    // 2nd output decays, so revert with error InputAndOutputDecay().
    function testBothInputAndOutputDecay() public {
        DutchOutput[] memory dutchOutputs = new DutchOutput[](2);
        dutchOutputs[0] = DutchOutput(address(0), 1000, 1000, address(0), false);
        dutchOutputs[1] = DutchOutput(address(0), 1000, 900, address(0), false);
        DutchLimitOrder memory dlo = DutchLimitOrder(
            OrderInfoBuilder.init(address(reactor)).withDeadline(1659130540),
            1659130500,
            1659130540,
            DutchInput(address(0), 100, 110),
            dutchOutputs
        );
        vm.expectRevert(DutchLimitOrderReactor.InputAndOutputDecay.selector);
        bytes memory sig = hex"1234";
        reactor.resolveOrder(SignedOrder(abi.encode(dlo), sig));
    }

    function testInputDecayIncorrectAmounts() public {
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(0), 1000, 1000, address(0), false);
        DutchLimitOrder memory dlo = DutchLimitOrder(
            OrderInfoBuilder.init(address(reactor)).withDeadline(1659130540),
            1659130500,
            1659130540,
            DutchInput(address(0), 110, 100),
            dutchOutputs
        );
        vm.expectRevert(DutchLimitOrderReactor.IncorrectAmounts.selector);
        bytes memory sig = hex"1234";
        reactor.resolveOrder(SignedOrder(abi.encode(dlo), sig));
    }

    function testOutputDecayIncorrectAmounts() public {
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(0), 1000, 1100, address(0), false);
        DutchLimitOrder memory dlo = DutchLimitOrder(
            OrderInfoBuilder.init(address(reactor)).withDeadline(1659130540),
            1659130500,
            1659130540,
            DutchInput(address(0), 100, 100),
            dutchOutputs
        );
        vm.expectRevert(DutchLimitOrderReactor.IncorrectAmounts.selector);
        bytes memory sig = hex"1234";
        reactor.resolveOrder(SignedOrder(abi.encode(dlo), sig));
    }

    function testInputDecayStartTimeAfterNow() public {
        uint256 mockNow = 1659050541;
        vm.warp(mockNow);
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(0), 1000, 1000, address(0), false);
        DutchLimitOrder memory dlo = DutchLimitOrder(
            OrderInfoBuilder.init(address(reactor)).withDeadline(1659130540),
            mockNow + 1,
            1659130540,
            DutchInput(address(0), 2000, 2500),
            dutchOutputs
        );
        bytes memory sig = hex"1234";
        ResolvedOrder memory resolvedOrder = reactor.resolveOrder(SignedOrder(abi.encode(dlo), sig));
        assertEq(resolvedOrder.input.amount, 2000);
    }

    // 2000+(2500-2000)*(20801/70901) = 2146
    function testInputDecayNowBetweenStartAndEnd() public {
        uint256 mockNow = 1659050541;
        vm.warp(mockNow);
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(0), 1000, 1000, address(0), false);
        DutchLimitOrder memory dlo = DutchLimitOrder(
            OrderInfoBuilder.init(address(reactor)).withDeadline(1659100641),
            1659029740,
            1659100641,
            DutchInput(address(0), 2000, 2500),
            dutchOutputs
        );
        bytes memory sig = hex"1234";
        ResolvedOrder memory resolvedOrder = reactor.resolveOrder(SignedOrder(abi.encode(dlo), sig));
        assertEq(resolvedOrder.input.amount, 2146);
    }
}

// This suite of tests test execution with a mock fill contract.
contract DutchLimitOrderReactorExecuteTest is Test, PermitSignature, ReactorEvents, GasSnapshot {
    using OrderInfoBuilder for OrderInfo;
    using DutchLimitOrderLib for DutchLimitOrder;

    address constant PROTOCOL_FEE_RECIPIENT = address(1);
    uint256 constant PROTOCOL_FEE_BPS = 5000;

    MockFillContract fillContract;
    MockERC20 tokenIn;
    MockERC20 tokenOut;
    uint256 makerPrivateKey;
    address maker;
    DutchLimitOrderReactor reactor;
    Permit2 permit2;

    function setUp() public {
        fillContract = new MockFillContract();
        tokenIn = new MockERC20("Input", "IN", 18);
        tokenOut = new MockERC20("Output", "OUT", 18);
        makerPrivateKey = 0x12341234;
        maker = vm.addr(makerPrivateKey);
        permit2 = new Permit2();
        reactor = new DutchLimitOrderReactor(address(permit2), PROTOCOL_FEE_BPS, PROTOCOL_FEE_RECIPIENT);
    }

    // Execute a single order, input = 1 and outputs = [2].
    function testExecute() public {
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn.mint(address(maker), inputAmount);
        tokenOut.mint(address(fillContract), outputAmount);
        tokenIn.forceApprove(maker, address(permit2), type(uint256).max);

        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount, outputAmount, maker)
        });

        vm.expectEmit(false, false, false, true);
        emit Fill(order.hash(), address(this), order.info.nonce, maker);
        snapStart("DutchExecuteSingle");
        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey, address(permit2), order)),
            address(fillContract),
            bytes("")
        );
        snapEnd();
        assertEq(tokenOut.balanceOf(maker), outputAmount);
        assertEq(tokenIn.balanceOf(address(fillContract)), inputAmount);
    }

    // Execute 2 dutch limit orders. The 1st one has input = 1, outputs = [2]. The 2nd one
    // has input = 2, outputs = [4].
    function testExecuteBatch() public {
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn.mint(address(maker), inputAmount * 3);
        tokenOut.mint(address(fillContract), 6 * 10 ** 18);
        tokenIn.forceApprove(maker, address(permit2), type(uint256).max);

        DutchLimitOrder[] memory orders = new DutchLimitOrder[](2);
        orders[0] = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount, outputAmount, maker)
        });
        orders[1] = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100).withNonce(
                1
                ),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn), inputAmount * 2, inputAmount * 2),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount * 2, outputAmount * 2, maker)
        });

        vm.expectEmit(false, false, false, true);
        emit Fill(orders[0].hash(), address(this), orders[0].info.nonce, maker);
        vm.expectEmit(false, false, false, true);
        emit Fill(orders[1].hash(), address(this), orders[1].info.nonce, maker);
        snapStart("DutchExecuteBatch");
        reactor.executeBatch(generateSignedOrders(orders), address(fillContract), bytes(""));
        snapEnd();
        assertEq(tokenOut.balanceOf(maker), 6000000000000000000);
        assertEq(tokenIn.balanceOf(address(fillContract)), 3000000000000000000);
    }

    // Execute 3 dutch limit orders. Have the 3rd one signed by a different maker.
    // Order 1: Input = 1, outputs = [2, 1]
    // Order 2: Input = 2, outputs = [3]
    // Order 3: Input = 3, outputs = [3,4,5]
    function testExecuteBatchMultipleOutputs() public {
        uint256 makerPrivateKey2 = 0x12341235;
        address maker2 = vm.addr(makerPrivateKey2);

        tokenIn.mint(address(maker), 3 * 10 ** 18);
        tokenIn.mint(address(maker2), 3 * 10 ** 18);
        tokenOut.mint(address(fillContract), 18 * 10 ** 18);
        tokenIn.forceApprove(maker, address(permit2), type(uint256).max);
        tokenIn.forceApprove(maker2, address(permit2), type(uint256).max);

        // Build the 3 orders
        DutchLimitOrder[] memory orders = new DutchLimitOrder[](3);

        uint256[] memory startAmounts0 = new uint256[](2);
        startAmounts0[0] = 2 * 10 ** 18;
        startAmounts0[1] = 10 ** 18;
        uint256[] memory endAmounts0 = new uint256[](2);
        endAmounts0[0] = startAmounts0[0];
        endAmounts0[1] = startAmounts0[1];
        orders[0] = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn), 10 ** 18, 10 ** 18),
            outputs: OutputsBuilder.multipleDutch(address(tokenOut), startAmounts0, endAmounts0, maker)
        });

        orders[1] = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100).withNonce(
                1
                ),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn), 2 * 10 ** 18, 2 * 10 ** 18),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), 3 * 10 ** 18, 3 * 10 ** 18, maker)
        });

        uint256[] memory startAmounts2 = new uint256[](3);
        startAmounts2[0] = 3 * 10 ** 18;
        startAmounts2[1] = 4 * 10 ** 18;
        startAmounts2[2] = 5 * 10 ** 18;
        uint256[] memory endAmounts2 = new uint256[](3);
        endAmounts2[0] = startAmounts2[0];
        endAmounts2[1] = startAmounts2[1];
        endAmounts2[2] = startAmounts2[2];
        orders[2] = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker2).withDeadline(block.timestamp + 100).withNonce(
                2
                ),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn), 3 * 10 ** 18, 3 * 10 ** 18),
            outputs: OutputsBuilder.multipleDutch(address(tokenOut), startAmounts2, endAmounts2, maker2)
        });
        SignedOrder[] memory signedOrders = generateSignedOrders(orders);
        // different maker
        signedOrders[2].sig = signOrder(makerPrivateKey2, address(permit2), orders[2]);

        vm.expectEmit(false, false, false, true);
        emit Fill(orders[0].hash(), address(this), orders[0].info.nonce, maker);
        vm.expectEmit(false, false, false, true);
        emit Fill(orders[1].hash(), address(this), orders[1].info.nonce, maker);
        vm.expectEmit(false, false, false, true);
        emit Fill(orders[2].hash(), address(this), orders[2].info.nonce, maker2);
        reactor.executeBatch(signedOrders, address(fillContract), bytes(""));
        assertEq(tokenOut.balanceOf(maker), 6 * 10 ** 18);
        assertEq(tokenOut.balanceOf(maker2), 12 * 10 ** 18);
        assertEq(tokenIn.balanceOf(address(fillContract)), 6 * 10 ** 18);
    }

    // Execute 2 dutch limit orders. The 1st one has input = 1, outputs = [2]. The 2nd one
    // has input = 2, outputs = [4]. However, only mint 5 output to fillContract, so there
    // will be an overflow error when reactor tries to transfer out 4 output out of the
    // fillContract for the second order.
    function testExecuteBatchInsufficientOutput() public {
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn.mint(address(maker), inputAmount * 3);
        tokenOut.mint(address(fillContract), 5 * 10 ** 18);
        tokenIn.forceApprove(maker, address(permit2), type(uint256).max);

        DutchLimitOrder[] memory orders = new DutchLimitOrder[](2);
        orders[0] = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount, outputAmount, maker)
        });
        orders[1] = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100).withNonce(
                1
                ),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn), inputAmount * 2, inputAmount * 2),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount * 2, outputAmount * 2, maker)
        });

        vm.expectRevert("TRANSFER_FROM_FAILED");
        reactor.executeBatch(generateSignedOrders(orders), address(fillContract), bytes(""));
    }

    function generateSignedOrders(DutchLimitOrder[] memory orders) private view returns (SignedOrder[] memory result) {
        result = new SignedOrder[](orders.length);
        for (uint256 i = 0; i < orders.length; i++) {
            bytes memory sig = signOrder(makerPrivateKey, address(permit2), orders[i]);
            result[i] = SignedOrder(abi.encode(orders[i]), sig);
        }
    }
}
