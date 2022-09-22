// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {OrderInfo} from "../../src/base/ReactorStructs.sol";
import {OrderInfoLib} from "../../src/lib/OrderInfoLib.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";

contract OrderInfoLibTest is Test {
    using OrderInfoBuilder for OrderInfo;
    using OrderInfoLib for OrderInfo;

    function testInvalidReactor() public {
        vm.expectRevert(OrderInfoLib.InvalidReactor.selector);
        OrderInfoBuilder.init(address(0)).validate();
    }

    function testDeadlinePassed() public {
        vm.expectRevert(OrderInfoLib.DeadlinePassed.selector);
        uint256 timestamp = block.timestamp;
        vm.warp(timestamp + 100);
        OrderInfoBuilder.init(address(this)).withDeadline(block.timestamp - 1).validate();
    }

    function testValid() public view {
        OrderInfoBuilder.init(address(this)).validate();
    }
}
