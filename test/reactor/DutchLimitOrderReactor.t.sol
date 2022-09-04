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
import {OrderInfo, TokenAmount} from "../../src/lib/ReactorStructs.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {MockERC20} from "../../src/test/MockERC20.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {MockFillContract} from "../../src/test/MockFillContract.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
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
        ResolvedOrder memory resolvedOrder = reactor.resolve(dlo);
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
        ResolvedOrder memory resolvedOrder = reactor.resolve(dlo);
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
        ResolvedOrder memory resolvedOrder = reactor.resolve(dlo);
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
        ResolvedOrder memory resolvedOrder = reactor.resolve(dlo);
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
        ResolvedOrder memory resolvedOrder = reactor.resolve(dlo);
        assertEq(resolvedOrder.outputs[0].amount, 1000);

        vm.warp(1659030748);
        resolvedOrder = reactor.resolve(dlo);
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
        reactor.validate(dlo);
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
        reactor.validate(dlo);
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
        reactor.validate(dlo);
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
        reactor.validate(dlo);
    }
}

// This suite of tests test execution with a mock fill contract.
contract DutchLimitOrderReactorExecuteTest is Test, PermitSignature {
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

    function testExecute() public {
        uint inputAmount = 10 ** 18;
        uint outputAmount = 2 * inputAmount;

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

        reactor.execute(
            order,
            getPermitSignature(
                vm,
                makerPrivateKey,
                address(permitPost),
                Permit({
                    token: address(tokenIn),
                    spender: address(reactor),
                    maxAmount: inputAmount,
                    deadline: order.info.deadline
                }),
                0,
                uint256(keccak256(abi.encode(order)))
            ),
            address(fillContract),
            bytes("")
        );
        assertEq(tokenOut.balanceOf(maker), 2000000000000000000);
        assertEq(tokenIn.balanceOf(address(fillContract)), 1000000000000000000);
    }
}