// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {OrderInfo, ResolvedOrder} from "../../src/base/ReactorStructs.sol";
import {ResolvedOrderLib} from "../../src/lib/ResolvedOrderLib.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {MockResolvedOrderLib} from "../util/mock/MockResolvedOrderLib.sol";
import {MockValidationContract} from "../util/mock/MockValidationContract.sol";

contract ResolvedOrderLibTest is Test {
    using OrderInfoBuilder for OrderInfo;

    MockResolvedOrderLib private resolvedOrderLib;
    ResolvedOrder private mockResolvedOrder;

    function setUp() public {
        resolvedOrderLib = new MockResolvedOrderLib();
    }

    function testInvalidReactor() public {
        mockResolvedOrder.info = OrderInfoBuilder.init(address(0));

        vm.expectRevert(ResolvedOrderLib.InvalidReactor.selector);
        resolvedOrderLib.validate(mockResolvedOrder, address(0));
    }

    function testDeadlinePassed() public {
        uint256 timestamp = block.timestamp;
        vm.warp(timestamp + 100);
        mockResolvedOrder.info = OrderInfoBuilder.init(address(resolvedOrderLib)).withDeadline(block.timestamp - 1);

        vm.expectRevert(ResolvedOrderLib.DeadlinePassed.selector);
        resolvedOrderLib.validate(mockResolvedOrder, address(0));
    }

    function testValid() public {
        mockResolvedOrder.info = OrderInfoBuilder.init(address(resolvedOrderLib));
        resolvedOrderLib.validate(mockResolvedOrder, address(0));
    }

    function testValidationContractInvalid() public {
        MockValidationContract validationContract = new MockValidationContract();
        validationContract.setValid(false);
        vm.expectRevert(ResolvedOrderLib.ValidationFailed.selector);
        mockResolvedOrder.info =
            OrderInfoBuilder.init(address(resolvedOrderLib)).withValidationContract(address(validationContract));
        resolvedOrderLib.validate(mockResolvedOrder, address(0));
    }

    function testValidationContractValid() public {
        MockValidationContract validationContract = new MockValidationContract();
        validationContract.setValid(true);
        mockResolvedOrder.info =
            OrderInfoBuilder.init(address(resolvedOrderLib)).withValidationContract(address(validationContract));
        resolvedOrderLib.validate(mockResolvedOrder, address(0));
    }
}
