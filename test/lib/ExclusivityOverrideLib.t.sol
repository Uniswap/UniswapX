// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {MockExclusivityOverrideLib} from "../util/mock/MockExclusivityOverrideLib.sol";
import {ExclusivityOverrideLib} from "../../src/lib/ExclusivityOverrideLib.sol";
import {OrderInfo, ResolvedOrder, OutputToken} from "../../src/base/ReactorStructs.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";

contract ExclusivityOverrideLibTest is Test {
    MockExclusivityOverrideLib exclusivity;
    address token1;
    address token2;
    address recipient;

    function setUp() public {
        exclusivity = new MockExclusivityOverrideLib();
        token1 = makeAddr("token1");
        token2 = makeAddr("token2");
        recipient = makeAddr("recipient");
    }

    function testExclusivity(address exclusive) public {
        vm.assume(exclusive != address(0));
        vm.prank(exclusive);
        assertEq(exclusivity.checkExclusivity(exclusive, block.timestamp + 1), true);
    }

    function testExclusivityFail(address caller, address exclusive, uint256 nowTime, uint256 exclusiveTimestamp)
        public
    {
        vm.assume(nowTime <= exclusiveTimestamp);
        vm.assume(caller != exclusive);
        vm.assume(exclusive != address(0));
        vm.warp(nowTime);
        vm.prank(caller);
        assertEq(exclusivity.checkExclusivity(exclusive, exclusiveTimestamp), false);
    }

    function testNoExclusivity(address caller, uint256 nowTime, uint256 exclusiveTimestamp) public {
        vm.warp(nowTime);
        vm.prank(caller);
        assertEq(exclusivity.checkExclusivity(address(0), exclusiveTimestamp), true);
    }

    function testExclusivityPeriodOver(address caller, uint256 nowTime, uint256 exclusiveTimestamp) public {
        vm.assume(nowTime > exclusiveTimestamp);
        vm.warp(nowTime);
        vm.prank(caller);
        assertEq(exclusivity.checkExclusivity(address(1), exclusiveTimestamp), true);
    }

    function testHandleOverridePass(address exclusive, uint256 overrideAmt, uint128 amount) public {
        vm.assume(overrideAmt < 10000);
        ResolvedOrder memory order;
        order.outputs = OutputsBuilder.single(token1, amount, recipient);
        vm.prank(exclusive);
        ResolvedOrder memory handled = exclusivity.handleOverride(order, exclusive, block.timestamp + 1, overrideAmt);
        // no changes
        assertEq(handled.outputs[0].amount, amount);
        assertEq(handled.outputs[0].recipient, recipient);
    }

    function testHandleOverridePassNoExclusivity(address caller, uint256 overrideAmt, uint128 amount) public {
        vm.assume(overrideAmt < 10000);
        ResolvedOrder memory order;
        order.outputs = OutputsBuilder.single(token1, amount, recipient);
        vm.prank(caller);
        ResolvedOrder memory handled = exclusivity.handleOverride(order, address(0), block.timestamp + 1, overrideAmt);
        // no changes
        assertEq(handled.outputs[0].amount, amount);
        assertEq(handled.outputs[0].recipient, recipient);
    }

    function testHandleOverridePassWindowPassed(address caller, address exclusive, uint256 overrideAmt, uint128 amount)
        public
    {
        vm.assume(overrideAmt < 10000);
        vm.assume(exclusive != address(0));
        vm.assume(caller != exclusive);
        ResolvedOrder memory order;
        order.outputs = OutputsBuilder.single(token1, amount, recipient);
        vm.warp(100);
        vm.prank(caller);
        ResolvedOrder memory handled = exclusivity.handleOverride(order, address(0), 99, overrideAmt);
        // no changes
        assertEq(handled.outputs[0].amount, amount);
        assertEq(handled.outputs[0].recipient, recipient);
    }

    function testHandleOverrideStrict(address caller, address exclusive, uint128 amount) public {
        vm.assume(caller != exclusive);
        vm.assume(exclusive != address(0));
        ResolvedOrder memory order;
        order.outputs = OutputsBuilder.single(token1, amount, recipient);
        vm.prank(caller);
        vm.expectRevert(ExclusivityOverrideLib.NoExclusiveOverride.selector);
        exclusivity.handleOverride(order, exclusive, block.timestamp + 1, 0);
    }

    function testHandleOverride() public {
        ResolvedOrder memory order;
        order.outputs = OutputsBuilder.single(token1, 1 ether, recipient);
        uint256 overrideAmt = 3000;
        vm.prank(address(2));
        ResolvedOrder memory handled = exclusivity.handleOverride(order, address(1), block.timestamp + 1, overrideAmt);
        // assert overrideAmt applied
        assertEq(handled.outputs[0].amount, 1.3 ether);
        assertEq(handled.outputs[0].recipient, recipient);
    }

    function testHandleOverrideApplied(address caller, address exclusive, uint256 overrideAmt, uint128 amount) public {
        vm.assume(caller != exclusive);
        vm.assume(exclusive != address(0));
        vm.assume(overrideAmt < 10000 && overrideAmt > 0);
        ResolvedOrder memory order;
        order.outputs = OutputsBuilder.single(token1, amount, recipient);
        vm.prank(caller);
        ResolvedOrder memory handled = exclusivity.handleOverride(order, exclusive, block.timestamp + 1, overrideAmt);
        // assert overrideAmt applied
        assertEq(handled.outputs[0].amount, amount * (10000 + overrideAmt) / 10000);
        assertEq(handled.outputs[0].recipient, recipient);
    }

    function testHandleOverrideAppliedMultiOutput(
        address caller,
        address exclusive,
        uint256 overrideAmt,
        uint128[] memory fuzzAmounts
    ) public {
        vm.assume(caller != exclusive);
        vm.assume(exclusive != address(0));
        vm.assume(overrideAmt < 10000 && overrideAmt > 0);
        uint256[] memory amounts = new uint256[](fuzzAmounts.length);
        for (uint256 i = 0; i < fuzzAmounts.length; i++) {
            amounts[i] = fuzzAmounts[i];
        }

        ResolvedOrder memory order;
        order.outputs = OutputsBuilder.multiple(token1, amounts, recipient);
        vm.prank(caller);
        ResolvedOrder memory handled = exclusivity.handleOverride(order, exclusive, block.timestamp + 1, overrideAmt);
        // assert overrideAmt applied
        for (uint256 i = 0; i < amounts.length; i++) {
            assertEq(handled.outputs[i].amount, amounts[i] * (10000 + overrideAmt) / 10000);
            assertEq(handled.outputs[i].recipient, recipient);
        }
    }
}
