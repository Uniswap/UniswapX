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
        vm.assume(inputAmountAddition > 0);
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
        assertTrue(order1.hash() != order2.hash());
    }

    function testHashChangesWhenInfoDeadlineChanges(uint256 deadlineAddition) public {
        vm.assume(type(uint256).max - deadlineAddition > 100);
        vm.assume(deadlineAddition > 0);
        DutchLimitOrder memory order1 = DutchLimitOrder({
            info: OrderInfoBuilder.init(REACTOR).withOfferer(MAKER).withDeadline(block.timestamp + 100),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: DutchInput(TOKEN_IN, ONE, ONE),
            outputs: OutputsBuilder.singleDutch(TOKEN_OUT, ONE, 0, MAKER)
        });
        DutchLimitOrder memory order2 = DutchLimitOrder({
            info: OrderInfoBuilder.init(REACTOR).withOfferer(MAKER).withDeadline(block.timestamp + 100 + deadlineAddition),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: DutchInput(TOKEN_IN, ONE, ONE),
            outputs: OutputsBuilder.singleDutch(TOKEN_OUT, ONE, 0, MAKER)
        });
        assertTrue(order1.hash() != order2.hash());
    }

    function testHashChangesWhenInfoReactorChanges(address randomReactor) public {
        vm.assume(REACTOR != randomReactor);
        DutchLimitOrder memory order1 = DutchLimitOrder({
            info: OrderInfoBuilder.init(REACTOR).withOfferer(MAKER).withDeadline(block.timestamp + 100),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: DutchInput(TOKEN_IN, ONE, ONE),
            outputs: OutputsBuilder.singleDutch(TOKEN_OUT, ONE, 0, MAKER)
        });
        DutchLimitOrder memory order2 = DutchLimitOrder({
            info: OrderInfoBuilder.init(randomReactor).withOfferer(MAKER).withDeadline(block.timestamp + 100),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: DutchInput(TOKEN_IN, ONE, ONE),
            outputs: OutputsBuilder.singleDutch(TOKEN_OUT, ONE, 0, MAKER)
        });
        assertTrue(order1.hash() != order2.hash());
    }

    function testHashChangesWhenInfoOffererChanges(address randomOfferer) public {
        vm.assume(MAKER != randomOfferer);
        DutchLimitOrder memory order1 = DutchLimitOrder({
            info: OrderInfoBuilder.init(REACTOR).withOfferer(MAKER).withDeadline(block.timestamp + 100),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: DutchInput(TOKEN_IN, ONE, ONE),
            outputs: OutputsBuilder.singleDutch(TOKEN_OUT, ONE, 0, MAKER)
        });
        DutchLimitOrder memory order2 = DutchLimitOrder({
            info: OrderInfoBuilder.init(REACTOR).withOfferer(randomOfferer).withDeadline(block.timestamp + 100),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: DutchInput(TOKEN_IN, ONE, ONE),
            outputs: OutputsBuilder.singleDutch(TOKEN_OUT, ONE, 0, MAKER)
        });
        assertTrue(order1.hash() != order2.hash());
    }

    function testHashChangesWhenInfoNonceChanges(uint256 randomNonce) public {
        vm.assume(randomNonce > 0);
        DutchLimitOrder memory order1 = DutchLimitOrder({
            info: OrderInfoBuilder.init(REACTOR).withOfferer(MAKER).withDeadline(block.timestamp + 100),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: DutchInput(TOKEN_IN, ONE, ONE),
            outputs: OutputsBuilder.singleDutch(TOKEN_OUT, ONE, 0, MAKER)
        });
        DutchLimitOrder memory order2 = DutchLimitOrder({
            info: OrderInfoBuilder.init(REACTOR).withOfferer(MAKER).withDeadline(block.timestamp + 100).withNonce(
                randomNonce
                ),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: DutchInput(TOKEN_IN, ONE, ONE),
            outputs: OutputsBuilder.singleDutch(TOKEN_OUT, ONE, 0, MAKER)
        });
        assertTrue(order1.hash() != order2.hash());
    }

    function testHashChangesWhenInfoValidationContractChanges(address randomValidationContract) public {
        vm.assume(randomValidationContract != address(0));
        DutchLimitOrder memory order1 = DutchLimitOrder({
            info: OrderInfoBuilder.init(REACTOR).withOfferer(MAKER).withDeadline(block.timestamp + 100),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: DutchInput(TOKEN_IN, ONE, ONE),
            outputs: OutputsBuilder.singleDutch(TOKEN_OUT, ONE, 0, MAKER)
        });
        DutchLimitOrder memory order2 = DutchLimitOrder({
            info: OrderInfoBuilder.init(REACTOR).withOfferer(MAKER).withDeadline(block.timestamp + 100)
                .withValidationContract(randomValidationContract),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: DutchInput(TOKEN_IN, ONE, ONE),
            outputs: OutputsBuilder.singleDutch(TOKEN_OUT, ONE, 0, MAKER)
        });
        assertTrue(order1.hash() != order2.hash());
    }

    function testHashChangesWhenStartTimeChanges(uint256 startTimeAdjustment) public {
        vm.assume(startTimeAdjustment != 100);
        vm.assume(startTimeAdjustment < 1000);
        DutchLimitOrder memory order1 = DutchLimitOrder({
            info: OrderInfoBuilder.init(REACTOR).withOfferer(MAKER).withDeadline(block.timestamp + 100),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: DutchInput(TOKEN_IN, ONE, ONE),
            outputs: OutputsBuilder.singleDutch(TOKEN_OUT, ONE, 0, MAKER)
        });
        DutchLimitOrder memory order2 = DutchLimitOrder({
            info: OrderInfoBuilder.init(REACTOR).withOfferer(MAKER).withDeadline(block.timestamp + 100),
            startTime: block.timestamp - startTimeAdjustment,
            endTime: block.timestamp + 100,
            input: DutchInput(TOKEN_IN, ONE, ONE),
            outputs: OutputsBuilder.singleDutch(TOKEN_OUT, ONE, 0, MAKER)
        });
        assertTrue(order1.hash() != order2.hash());
    }

    function testHashChangesWhenEndTimeChanges(uint256 endTimeAdjustment) public {
        vm.assume(endTimeAdjustment != 100);
        vm.assume(endTimeAdjustment < 100000000);
        DutchLimitOrder memory order1 = DutchLimitOrder({
            info: OrderInfoBuilder.init(REACTOR).withOfferer(MAKER).withDeadline(block.timestamp + 100),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: DutchInput(TOKEN_IN, ONE, ONE),
            outputs: OutputsBuilder.singleDutch(TOKEN_OUT, ONE, 0, MAKER)
        });
        DutchLimitOrder memory order2 = DutchLimitOrder({
            info: OrderInfoBuilder.init(REACTOR).withOfferer(MAKER).withDeadline(block.timestamp + 100),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + endTimeAdjustment,
            input: DutchInput(TOKEN_IN, ONE, ONE),
            outputs: OutputsBuilder.singleDutch(TOKEN_OUT, ONE, 0, MAKER)
        });
        assertTrue(order1.hash() != order2.hash());
    }
}
