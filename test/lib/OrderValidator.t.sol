// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {OrderInfo} from "../../src/lib/ReactorStructs.sol";
import {OrderValidator} from "../../src/lib/OrderValidator.sol";
import {MockOrderValidator} from "../util/mock/MockOrderValidator.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";

contract OrderValidatorTest is Test {
    using OrderInfoBuilder for OrderInfo;

    MockOrderValidator validator;

    function setUp() public {
        validator = new MockOrderValidator();
    }

    function testInvalidReactor() public {
        vm.expectRevert(OrderValidator.InvalidReactor.selector);
        validator.validate(OrderInfoBuilder.init(address(0)));
    }

    function testDeadlinePassed() public {
        vm.expectRevert(OrderValidator.DeadlinePassed.selector);
        uint256 timestamp = block.timestamp;
        vm.warp(timestamp + 100);
        validator.validate(OrderInfoBuilder.init(address(validator)).withDeadline(block.timestamp - 1));
    }

    function testValid() public view {
        validator.validate(OrderInfoBuilder.init(address(validator)));
    }
}
