// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {MockExclusivityLib} from "../util/mock/MockExclusivityLib.sol";
import {ExclusivityLib} from "../../src/lib/ExclusivityLib.sol";
import {OrderInfo, ResolvedOrder, OutputToken} from "../../src/base/ReactorStructs.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";

contract ExclusivityLibTest is Test {
    using FixedPointMathLib for uint256;

    MockExclusivityLib exclusivity;
    address token1;
    address token2;
    address recipient;

    uint256 blockNumberish;

    function setUp() public {
        exclusivity = new MockExclusivityLib();
        token1 = makeAddr("token1");
        token2 = makeAddr("token2");
        recipient = makeAddr("recipient");
        blockNumberish = block.number;
    }

    function testTimestampExclusivity(address exclusive) public {
        vm.assume(exclusive != address(0));
        vm.prank(exclusive);
        assertEq(exclusivity.hasFillingRights(exclusive, block.timestamp + 1, block.timestamp), true);
    }

    function testExclusivityFail(address caller, address exclusive, uint256 nowTime, uint256 exclusiveEnd) public {
        vm.assume(nowTime <= exclusiveEnd);
        vm.assume(caller != exclusive);
        vm.assume(exclusive != address(0));
        vm.prank(caller);
        assertEq(exclusivity.hasFillingRights(exclusive, exclusiveEnd, nowTime), false);
    }

    function testNoExclusivity(address caller, uint256 nowTime, uint256 exclusiveEnd) public {
        vm.prank(caller);
        assertEq(exclusivity.hasFillingRights(address(0), exclusiveEnd, nowTime), true);
    }

    function testExclusivityPeriodOver(address caller, uint256 nowTime, uint256 exclusiveEnd) public {
        vm.assume(nowTime > exclusiveEnd);
        vm.prank(caller);
        assertEq(exclusivity.hasFillingRights(address(1), exclusiveEnd, nowTime), true);
    }

    function testHandleExclusiveOverrideTimestampPass(address exclusive, uint256 overrideAmt, uint128 amount) public {
        vm.assume(overrideAmt < 10000);
        ResolvedOrder memory order;
        order.outputs = OutputsBuilder.single(token1, amount, recipient);
        vm.prank(exclusive);
        ResolvedOrder memory handled =
            exclusivity.handleExclusiveOverrideTimestamp(order, exclusive, block.timestamp + 1, overrideAmt);
        // no changes
        assertEq(handled.outputs[0].amount, amount);
        assertEq(handled.outputs[0].recipient, recipient);
    }

    function testHandleExclusiveOverrideBlockPass(address exclusive, uint256 overrideAmt, uint128 amount) public {
        vm.assume(overrideAmt < 10000);
        ResolvedOrder memory order;
        order.outputs = OutputsBuilder.single(token1, amount, recipient);
        vm.prank(exclusive);
        ResolvedOrder memory handled =
            exclusivity.handleExclusiveOverrideBlock(order, exclusive, block.number + 1, overrideAmt, blockNumberish);
        // no changes
        assertEq(handled.outputs[0].amount, amount);
        assertEq(handled.outputs[0].recipient, recipient);
    }

    function testHandleExclusiveOverrideTimestampPassNoExclusivity(address caller, uint256 overrideAmt, uint128 amount)
        public
    {
        vm.assume(overrideAmt < 10000);
        ResolvedOrder memory order;
        order.outputs = OutputsBuilder.single(token1, amount, recipient);
        vm.prank(caller);
        ResolvedOrder memory handled =
            exclusivity.handleExclusiveOverrideTimestamp(order, address(0), block.timestamp + 1, overrideAmt);
        // no changes
        assertEq(handled.outputs[0].amount, amount);
        assertEq(handled.outputs[0].recipient, recipient);
    }

    function testHandleExclusiveOverrideBlockPassNoExclusivity(address caller, uint256 overrideAmt, uint128 amount)
        public
    {
        vm.assume(overrideAmt < 10000);
        ResolvedOrder memory order;
        order.outputs = OutputsBuilder.single(token1, amount, recipient);
        vm.prank(caller);
        ResolvedOrder memory handled =
            exclusivity.handleExclusiveOverrideBlock(order, address(0), block.number + 1, overrideAmt, blockNumberish);
        // no changes
        assertEq(handled.outputs[0].amount, amount);
        assertEq(handled.outputs[0].recipient, recipient);
    }

    function testHandleExclusiveOverrideTimetampPassWindowPassed(
        address caller,
        address exclusive,
        uint256 overrideAmt,
        uint128 amount
    ) public {
        vm.assume(overrideAmt < 10000);
        vm.assume(exclusive != address(0));
        vm.assume(caller != exclusive);
        ResolvedOrder memory order;
        order.outputs = OutputsBuilder.single(token1, amount, recipient);
        vm.warp(100);
        vm.prank(caller);
        ResolvedOrder memory handled = exclusivity.handleExclusiveOverrideTimestamp(order, address(0), 99, overrideAmt);
        // no changes
        assertEq(handled.outputs[0].amount, amount);
        assertEq(handled.outputs[0].recipient, recipient);
    }

    function testHandleExclusiveOverrideBlockPassWindowPassed(
        address caller,
        address exclusive,
        uint256 overrideAmt,
        uint128 amount
    ) public {
        vm.assume(overrideAmt < 10000);
        vm.assume(exclusive != address(0));
        vm.assume(caller != exclusive);
        ResolvedOrder memory order;
        order.outputs = OutputsBuilder.single(token1, amount, recipient);
        vm.roll(100);
        vm.prank(caller);
        ResolvedOrder memory handled =
            exclusivity.handleExclusiveOverrideBlock(order, address(0), 99, overrideAmt, blockNumberish);
        // no changes
        assertEq(handled.outputs[0].amount, amount);
        assertEq(handled.outputs[0].recipient, recipient);
    }

    function testHandleExclusiveOverrideTimestampStrict(address caller, address exclusive, uint128 amount) public {
        vm.assume(caller != exclusive);
        vm.assume(exclusive != address(0));
        ResolvedOrder memory order;
        order.outputs = OutputsBuilder.single(token1, amount, recipient);
        vm.prank(caller);
        vm.expectRevert(ExclusivityLib.NoExclusiveOverride.selector);
        exclusivity.handleExclusiveOverrideTimestamp(order, exclusive, block.timestamp + 1, 0);
    }

    function testHandleExclusiveOverrideBlockStrict(address caller, address exclusive, uint128 amount) public {
        vm.assume(caller != exclusive);
        vm.assume(exclusive != address(0));
        ResolvedOrder memory order;
        order.outputs = OutputsBuilder.single(token1, amount, recipient);
        vm.prank(caller);
        vm.expectRevert(ExclusivityLib.NoExclusiveOverride.selector);
        exclusivity.handleExclusiveOverrideBlock(order, exclusive, block.number + 1, 0, blockNumberish);
    }

    function testHandleExclusiveOverrideTimestamp() public {
        ResolvedOrder memory order;
        order.outputs = OutputsBuilder.single(token1, 1 ether, recipient);
        uint256 overrideAmt = 3000;
        vm.prank(address(2));
        ResolvedOrder memory handled =
            exclusivity.handleExclusiveOverrideTimestamp(order, address(1), block.timestamp + 1, overrideAmt);
        // assert overrideAmt applied
        assertEq(handled.outputs[0].amount, 1.3 ether);
        assertEq(handled.outputs[0].recipient, recipient);
    }

    function testHandleExclusiveOverrideBlock() public {
        ResolvedOrder memory order;
        order.outputs = OutputsBuilder.single(token1, 1 ether, recipient);
        uint256 overrideAmt = 3000;
        vm.prank(address(2));
        ResolvedOrder memory handled =
            exclusivity.handleExclusiveOverrideBlock(order, address(1), block.number + 1, overrideAmt, blockNumberish);
        // assert overrideAmt applied
        assertEq(handled.outputs[0].amount, 1.3 ether);
        assertEq(handled.outputs[0].recipient, recipient);
    }

    function testHandleExclusiveOverrideTimetampRoundUp() public {
        ResolvedOrder memory order;
        order.outputs = OutputsBuilder.single(token1, 1 ether + 1, recipient);
        uint256 overrideAmt = 3000;
        vm.prank(address(2));
        ResolvedOrder memory handled =
            exclusivity.handleExclusiveOverrideTimestamp(order, address(1), block.timestamp + 1, overrideAmt);
        // assert overrideAmt applied
        assertEq(handled.outputs[0].amount, 1.3 ether + 2);
        assertEq(handled.outputs[0].recipient, recipient);
    }

    function testHandleExclusiveOverrideBlockRoundUp() public {
        ResolvedOrder memory order;
        order.outputs = OutputsBuilder.single(token1, 1 ether + 1, recipient);
        uint256 overrideAmt = 3000;
        vm.prank(address(2));
        ResolvedOrder memory handled =
            exclusivity.handleExclusiveOverrideBlock(order, address(1), block.number + 1, overrideAmt, blockNumberish);
        // assert overrideAmt applied
        assertEq(handled.outputs[0].amount, 1.3 ether + 2);
        assertEq(handled.outputs[0].recipient, recipient);
    }

    function testHandleExclusiveOverrideTimestampApplied(
        address caller,
        address exclusive,
        uint256 overrideAmt,
        uint128 amount
    ) public {
        vm.assume(caller != exclusive);
        vm.assume(exclusive != address(0));
        vm.assume(overrideAmt < 10000 && overrideAmt > 0);
        ResolvedOrder memory order;
        order.outputs = OutputsBuilder.single(token1, amount, recipient);
        vm.prank(caller);
        ResolvedOrder memory handled =
            exclusivity.handleExclusiveOverrideTimestamp(order, exclusive, block.timestamp + 1, overrideAmt);
        // assert overrideAmt applied
        assertEq(handled.outputs[0].amount, uint256(amount).mulDivUp(10000 + overrideAmt, 10000));
        assertEq(handled.outputs[0].recipient, recipient);
    }

    function testHandleExclusiveOverrideBlockApplied(
        address caller,
        address exclusive,
        uint256 overrideAmt,
        uint128 amount
    ) public {
        vm.assume(caller != exclusive);
        vm.assume(exclusive != address(0));
        vm.assume(overrideAmt < 10000 && overrideAmt > 0);
        ResolvedOrder memory order;
        order.outputs = OutputsBuilder.single(token1, amount, recipient);
        vm.prank(caller);
        ResolvedOrder memory handled =
            exclusivity.handleExclusiveOverrideBlock(order, exclusive, block.number + 1, overrideAmt, blockNumberish);
        // assert overrideAmt applied
        assertEq(handled.outputs[0].amount, uint256(amount).mulDivUp(10000 + overrideAmt, 10000));
        assertEq(handled.outputs[0].recipient, recipient);
    }

    function testHandleExclusiveOverrideTimestampAppliedMultiOutput(
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
        ResolvedOrder memory handled =
            exclusivity.handleExclusiveOverrideTimestamp(order, exclusive, block.timestamp + 1, overrideAmt);
        // assert overrideAmt applied
        for (uint256 i = 0; i < amounts.length; i++) {
            assertEq(handled.outputs[i].amount, uint256(amounts[i]).mulDivUp(10000 + overrideAmt, 10000));
            assertEq(handled.outputs[i].recipient, recipient);
        }
    }

    function testHandleExclusiveOverrideBlockAppliedMultiOutput(
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
        ResolvedOrder memory handled =
            exclusivity.handleExclusiveOverrideBlock(order, exclusive, block.number + 1, overrideAmt, blockNumberish);
        // assert overrideAmt applied
        for (uint256 i = 0; i < amounts.length; i++) {
            assertEq(handled.outputs[i].amount, uint256(amounts[i]).mulDivUp(10000 + overrideAmt, 10000));
            assertEq(handled.outputs[i].recipient, recipient);
        }
    }
}
