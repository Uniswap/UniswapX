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

    function testResolve() public {
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
                0
            ),
            1659029740,
            1659130540,
            TokenAmount(address(0), 12345),
            dutchOutputs
        );
        ResolvedOrder memory resolvedOrder = reactor.resolve(dlo);
        console.log(resolvedOrder.outputs[0].amount);
    }
}
