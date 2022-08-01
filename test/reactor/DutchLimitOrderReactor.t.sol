// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {DutchLimitOrderReactor, DutchLimitOrder, ResolvedOrder} from "../../src/reactor/dutch-limit/DutchLimitOrderReactor.sol";
import {DutchOutput} from "../../src/reactor/dutch-limit/DutchLimitOrderStructs.sol";
import {OrderInfo, TokenAmount} from "../../src/interfaces/ReactorStructs.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import "forge-std/console.sol";

contract LimitOrderReactorTest is Test {
    using OrderInfoBuilder for OrderInfo;

    DutchLimitOrderReactor reactor;

    function setUp() public {
        reactor = new DutchLimitOrderReactor();
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
        uint mockNow = 1659100541;
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
}
