// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {PermitPost, Permit} from "permitpost/PermitPost.sol";
import {
    DutchLimitOrderReactor,
    DutchLimitOrder,
    ResolvedOrder
} from "../../src/reactor/dutch-limit/DutchLimitOrderReactor.sol";
import {DutchOutput} from "../../src/reactor/dutch-limit/DutchLimitOrderStructs.sol";
import {OrderInfo, TokenAmount, Signature, SignedOrder} from "../../src/lib/ReactorStructs.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {MockFillContract} from "../util/mock/MockFillContract.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {ReactorEvents} from "../../src/lib/ReactorEvents.sol";
import "forge-std/console.sol";

// This suite of tests test validation and resolves.
contract DutchLimitOrderReactorValidationTest is Test {
    using OrderInfoBuilder for OrderInfo;

    DutchLimitOrderReactor reactor;
    PermitPost permitPost;

    function setUp() public {
        permitPost = new PermitPost();
        reactor = new DutchLimitOrderReactor(address(permitPost));
    }

    // 1000 - (1000-900) * (1659087340-1659029740) / (1659130540-1659029740) = 943
    function testResolveEndTimeAfterNow() public {
        vm.warp(1659087340);
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(0), 1000, 900, address(0));
        DutchLimitOrder memory dlo = DutchLimitOrder(
            OrderInfoBuilder.init(address(reactor)).withDeadline(1659130540),
            1659029740,
            1659130540,
            TokenAmount(address(0), 0),
            dutchOutputs
        );
        ResolvedOrder memory resolvedOrder = reactor.resolve(abi.encode(dlo));
        assertEq(resolvedOrder.outputs[0].amount, 943);
        assertEq(resolvedOrder.outputs.length, 1);
        assertEq(resolvedOrder.input.amount, 0);
        assertEq(resolvedOrder.input.token, address(0));
    }

    // Test that resolved amount = endAmount if end time is before now
    function testResolveEndTimeBeforeNow() public {
        uint256 mockNow = 1659100541;
        vm.warp(mockNow);
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(0), 1000, 900, address(0));
        DutchLimitOrder memory dlo = DutchLimitOrder(
            OrderInfoBuilder.init(address(reactor)).withDeadline(1659130540),
            1659029740,
            mockNow - 1,
            TokenAmount(address(0), 0),
            dutchOutputs
        );
        ResolvedOrder memory resolvedOrder = reactor.resolve(abi.encode(dlo));
        assertEq(resolvedOrder.outputs[0].amount, 900);
        assertEq(resolvedOrder.outputs.length, 1);
        assertEq(resolvedOrder.input.amount, 0);
        assertEq(resolvedOrder.input.token, address(0));
    }

    // Test multiple dutch outputs get resolved correctly. Use same time points as
    // testResolveEndTimeAfterNow().
    function testResolveMultipleDutchOutputs() public {
        vm.warp(1659087340);
        DutchOutput[] memory dutchOutputs = new DutchOutput[](3);
        dutchOutputs[0] = DutchOutput(address(0), 1000, 900, address(0));
        dutchOutputs[1] = DutchOutput(address(0), 10000, 9000, address(0));
        dutchOutputs[2] = DutchOutput(address(0), 2000, 1000, address(0));
        DutchLimitOrder memory dlo = DutchLimitOrder(
            OrderInfoBuilder.init(address(reactor)).withDeadline(1659130540),
            1659029740,
            1659130540,
            TokenAmount(address(0), 0),
            dutchOutputs
        );
        ResolvedOrder memory resolvedOrder = reactor.resolve(abi.encode(dlo));
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
        dutchOutputs[0] = DutchOutput(address(0), 1000, 900, address(0));
        DutchLimitOrder memory dlo = DutchLimitOrder(
            OrderInfoBuilder.init(address(reactor)).withDeadline(1659130540),
            1659029740,
            1659130540,
            TokenAmount(address(0), 0),
            dutchOutputs
        );
        ResolvedOrder memory resolvedOrder = reactor.resolve(abi.encode(dlo));
        assertEq(resolvedOrder.outputs[0].amount, 1000);
        assertEq(resolvedOrder.outputs.length, 1);
        assertEq(resolvedOrder.input.amount, 0);
        assertEq(resolvedOrder.input.token, address(0));
    }

    // At time 1659030747, output will still be 1000. One second later at 1659030748,
    // the first decay will occur and the output will be 999.
    function testResolveFirstDecay() public {
        vm.warp(1659030747);
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(0), 1000, 900, address(0));
        DutchLimitOrder memory dlo = DutchLimitOrder(
            OrderInfoBuilder.init(address(reactor)).withDeadline(1659130540),
            1659029740,
            1659130540,
            TokenAmount(address(0), 0),
            dutchOutputs
        );
        ResolvedOrder memory resolvedOrder = reactor.resolve(abi.encode(dlo));
        assertEq(resolvedOrder.outputs[0].amount, 1000);

        vm.warp(1659030748);
        resolvedOrder = reactor.resolve(abi.encode(dlo));
        assertEq(resolvedOrder.outputs[0].amount, 999);
    }

    function testValidateDutchEndTimeBeforeStart() public {
        vm.expectRevert(DutchLimitOrderReactor.EndTimeBeforeStart.selector);
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(0), 1000, 900, address(0));
        DutchLimitOrder memory dlo = DutchLimitOrder(
            OrderInfoBuilder.init(address(reactor)).withDeadline(1659130540),
            1659130541,
            1659130540,
            TokenAmount(address(0), 0),
            dutchOutputs
        );
        reactor.resolve(abi.encode(dlo));
    }

    function testValidateDutchEndTimeAfterStart() public view {
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(0), 1000, 900, address(0));
        DutchLimitOrder memory dlo = DutchLimitOrder(
            OrderInfoBuilder.init(address(reactor)).withDeadline(1659130540),
            1659120540,
            1659130540,
            TokenAmount(address(0), 0),
            dutchOutputs
        );
        reactor.resolve(abi.encode(dlo));
    }

    function testValidateDutchDeadlineBeforeEndTime() public {
        vm.expectRevert(DutchLimitOrderReactor.DeadlineBeforeEndTime.selector);
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(0), 1000, 900, address(0));
        DutchLimitOrder memory dlo = DutchLimitOrder(
            OrderInfoBuilder.init(address(reactor)).withDeadline(1659130530),
            1659120540,
            1659130540,
            TokenAmount(address(0), 0),
            dutchOutputs
        );
        reactor.resolve(abi.encode(dlo));
    }

    function testValidateDutchDeadlineAfterEndTime() public view {
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(0), 1000, 900, address(0));
        DutchLimitOrder memory dlo = DutchLimitOrder(
            OrderInfoBuilder.init(address(reactor)).withDeadline(1659130550),
            1659120540,
            1659130540,
            TokenAmount(address(0), 0),
            dutchOutputs
        );
        reactor.resolve(abi.encode(dlo));
    }
}

// This suite of tests test execution with a mock fill contract.
contract DutchLimitOrderReactorExecuteTest is Test, PermitSignature, ReactorEvents {
    using OrderInfoBuilder for OrderInfo;

    MockFillContract fillContract;
    MockERC20 tokenIn;
    MockERC20 tokenOut;
    uint256 makerPrivateKey;
    address maker;
    DutchLimitOrderReactor reactor;
    PermitPost permitPost;

    function setUp() public {
        fillContract = new MockFillContract();
        tokenIn = new MockERC20("Input", "IN", 18);
        tokenOut = new MockERC20("Output", "OUT", 18);
        makerPrivateKey = 0x12341234;
        maker = vm.addr(makerPrivateKey);
        permitPost = new PermitPost();
        reactor = new DutchLimitOrderReactor(address(permitPost));
    }

    // Execute a single order, input = 1 and outputs = [2].
    function testExecute() public {
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn.mint(address(maker), inputAmount);
        tokenOut.mint(address(fillContract), outputAmount);
        tokenIn.forceApprove(maker, address(permitPost), type(uint256).max);

        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: TokenAmount(address(tokenIn), inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount, outputAmount, maker)
        });

        vm.expectEmit(false, false, false, true);
        emit Fill(keccak256(abi.encode(order)), 0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84);
        reactor.execute(
            SignedOrder(
                abi.encode(order),
                signOrder(
                    vm, makerPrivateKey, address(permitPost), order.info, order.input, keccak256(abi.encode(order))
                )
            ),
            address(fillContract),
            bytes("")
        );
        assertEq(tokenOut.balanceOf(maker), 2000000000000000000);
        assertEq(tokenIn.balanceOf(address(fillContract)), 1000000000000000000);
    }

    // Execute 2 dutch limit orders. The 1st one has input = 1, outputs = [2]. The 2nd one
    // has input = 2, outputs = [4].
    function testExecuteBatch() public {
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn.mint(address(maker), inputAmount * 3);
        tokenOut.mint(address(fillContract), 6 * 10 ** 18);
        tokenIn.forceApprove(maker, address(permitPost), type(uint256).max);

        DutchLimitOrder[] memory orders = new DutchLimitOrder[](2);
        orders[0] = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: TokenAmount(address(tokenIn), inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount, outputAmount, maker)
        });
        orders[1] = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100).withNonce(
                1
                ),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: TokenAmount(address(tokenIn), inputAmount * 2),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount * 2, outputAmount * 2, maker)
        });

        vm.expectEmit(false, false, false, true);
        emit Fill(keccak256(abi.encode(orders[0])), address(this));
        vm.expectEmit(false, false, false, true);
        emit Fill(keccak256(abi.encode(orders[1])), address(this));
        reactor.executeBatch(generateSignedOrders(orders), address(fillContract), bytes(""));
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
        tokenIn.forceApprove(maker, address(permitPost), type(uint256).max);
        tokenIn.forceApprove(maker2, address(permitPost), type(uint256).max);

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
            input: TokenAmount(address(tokenIn), 10 ** 18),
            outputs: OutputsBuilder.multipleDutch(address(tokenOut), startAmounts0, endAmounts0, maker)
        });

        orders[1] = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100).withNonce(
                1
                ),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: TokenAmount(address(tokenIn), 2 * 10 ** 18),
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
            input: TokenAmount(address(tokenIn), 3 * 10 ** 18),
            outputs: OutputsBuilder.multipleDutch(address(tokenOut), startAmounts2, endAmounts2, maker2)
        });
        SignedOrder[] memory signedOrders = generateSignedOrders(orders);
        // different maker
        signedOrders[2].sig = signOrder(
            vm, makerPrivateKey2, address(permitPost), orders[2].info, orders[2].input, keccak256(abi.encode(orders[2]))
        );

        vm.expectEmit(false, false, false, true);
        emit Fill(keccak256(abi.encode(orders[0])), address(this));
        vm.expectEmit(false, false, false, true);
        emit Fill(keccak256(abi.encode(orders[1])), address(this));
        vm.expectEmit(false, false, false, true);
        emit Fill(keccak256(abi.encode(orders[2])), address(this));
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
        tokenIn.forceApprove(maker, address(permitPost), type(uint256).max);

        DutchLimitOrder[] memory orders = new DutchLimitOrder[](2);
        orders[0] = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: TokenAmount(address(tokenIn), inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount, outputAmount, maker)
        });
        orders[1] = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker).withDeadline(block.timestamp + 100).withNonce(
                1
                ),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: TokenAmount(address(tokenIn), inputAmount * 2),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), outputAmount * 2, outputAmount * 2, maker)
        });

        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        reactor.executeBatch(generateSignedOrders(orders), address(fillContract), bytes(""));
    }

    function generateSignedOrders(DutchLimitOrder[] memory orders) private returns (SignedOrder[] memory result) {
        result = new SignedOrder[](orders.length);
        for (uint256 i = 0; i < orders.length; i++) {
            Signature memory sig = signOrder(
                vm,
                makerPrivateKey,
                address(permitPost),
                orders[i].info,
                orders[i].input,
                keccak256(abi.encode(orders[i]))
            );
            result[i] = SignedOrder(abi.encode(orders[i]), sig);
        }
    }
}
