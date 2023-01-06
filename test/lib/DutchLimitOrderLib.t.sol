// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {OrderInfo, ResolvedOrder} from "../../src/base/ReactorStructs.sol";
import {DutchLimitOrderLib, DutchLimitOrder, DutchInput} from "../../src/lib/DutchLimitOrderLib.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import "forge-std/console.sol";

contract DutchLimitOrderLibTest is Test {
    using DutchLimitOrderLib for DutchLimitOrder;
    using OrderInfoBuilder for OrderInfo;

    address constant REACTOR = address(10);
    address constant MAKER = address(11);
    address constant TOKEN_IN = address(12);
    address constant TOKEN_OUT = address(13);
    uint256 constant ONE = 10 ** 18;

    function setUp() public {
        vm.warp(1000);
    }

    function testHashChangesWhenInputAmountChanges(uint256 inputAmount, uint256 inputAmountAddition) public {
        vm.assume(type(uint256).max - inputAmountAddition > inputAmount);
        DutchLimitOrder memory order1 = DutchLimitOrder({
            info: OrderInfoBuilder.init(REACTOR).withOfferer(MAKER).withDeadline(block.timestamp + 100),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: DutchInput(TOKEN_IN, inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(TOKEN_OUT, ONE, 0, MAKER)
        });
        DutchLimitOrder memory order2 = DutchLimitOrder({
            info: OrderInfoBuilder.init(REACTOR).withOfferer(MAKER).withDeadline(block.timestamp + 100),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: DutchInput(TOKEN_IN, inputAmount + inputAmountAddition, inputAmount + inputAmountAddition),
            outputs: OutputsBuilder.singleDutch(TOKEN_OUT, ONE, 0, MAKER)
        });
        console.logBytes32(order1.hash());
    }
}
