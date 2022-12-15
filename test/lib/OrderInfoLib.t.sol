// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {OrderInfo, ResolvedOrder} from "../../src/base/ReactorStructs.sol";
import {ResolvedOrderLib} from "../../src/lib/ResolvedOrderLib.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {MockOrderInfoLib} from "../util/mock/MockOrderInfoLib.sol";
import {MockValidationContract} from "../util/mock/MockValidationContract.sol";

contract OrderInfoLibTest is Test {
    using OrderInfoBuilder for OrderInfo;

    MockOrderInfoLib private orderInfoLib;
    ResolvedOrder private mockResolvedOrder;

    function setUp() public {
        orderInfoLib = new MockOrderInfoLib();
    }

    function testInvalidReactor() public {
        mockResolvedOrder.info = OrderInfoBuilder.init(address(0));

        vm.expectRevert(ResolvedOrderLib.InvalidReactor.selector);
        orderInfoLib.validate(mockResolvedOrder, address(0));
    }

    function testDeadlinePassed() public {
        uint256 timestamp = block.timestamp;
        vm.warp(timestamp + 100);
        mockResolvedOrder.info = OrderInfoBuilder.init(address(orderInfoLib)).withDeadline(block.timestamp - 1);

        vm.expectRevert(ResolvedOrderLib.DeadlinePassed.selector);
        orderInfoLib.validate(mockResolvedOrder, address(0));
    }

    function testValid() public {
        mockResolvedOrder.info = OrderInfoBuilder.init(address(orderInfoLib));
        orderInfoLib.validate(mockResolvedOrder, address(0));
    }

    function testValidationContractInvalid() public {
        MockValidationContract validationContract = new MockValidationContract();
        validationContract.setValid(false);
        vm.expectRevert(ResolvedOrderLib.ValidationFailed.selector);
        mockResolvedOrder.info =
            OrderInfoBuilder.init(address(orderInfoLib)).withValidationContract(address(validationContract));
        orderInfoLib.validate(mockResolvedOrder, address(0));
    }

    function testValidationContractValid() public {
        MockValidationContract validationContract = new MockValidationContract();
        validationContract.setValid(true);
        mockResolvedOrder.info =
            OrderInfoBuilder.init(address(orderInfoLib)).withValidationContract(address(validationContract));
        orderInfoLib.validate(mockResolvedOrder, address(0));
    }
}
