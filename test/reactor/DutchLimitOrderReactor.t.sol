// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {DutchLimitOrderReactor, DutchLimitOrder, ResolvedOrder} from "../../src/reactor/dutch-limit/DutchLimitOrderReactor.sol";
import {DutchOutput} from "../../src/reactor/dutch-limit/DutchLimitOrderStructs.sol";
import {OrderInfo, TokenAmount} from "../../src/interfaces/ReactorStructs.sol";
import "forge-std/console.sol";

contract LimitOrderReactorTest is Test {

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
            OrderInfo(
                address(0),
                address(0),
                address(0),
                '',
                0,
                1659130540
            ),
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
        uint now = 1659100541;
        vm.warp(now);
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(0), 1000, 900, address(0));
        DutchLimitOrder memory dlo = DutchLimitOrder(
            OrderInfo(
                address(0),
                address(0),
                address(0),
                '',
                0,
                1659130540
            ),
            1659029740,
            now - 1,
            TokenAmount(address(0), 0),
            dutchOutputs
        );
        ResolvedOrder memory resolvedOrder = reactor.resolve(dlo);
        assertEq(resolvedOrder.outputs[0].amount, 900);
        assertEq(resolvedOrder.outputs.length, 1);
        assertEq(resolvedOrder.input.amount, 0);
        assertEq(resolvedOrder.input.token, address(0));
    }
}
