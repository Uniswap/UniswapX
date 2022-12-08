// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {OrderInfo, ResolvedOrder} from "../../src/base/ReactorStructs.sol";
import {OrderInfoLib} from "../../src/lib/OrderInfoLib.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {MockOrderInfoLib} from "../util/mock/MockOrderInfoLib.sol";
import {MockValidationContract} from "../util/mock/MockValidationContract.sol";
import {RfqValidationContract} from "../../src/sample-validation-contracts/RfqValidationContract.sol";

contract OrderInfoLibTest is Test {
    using OrderInfoBuilder for OrderInfo;

    MockOrderInfoLib private orderInfoLib;
    ResolvedOrder private mockResolvedOrder;

    function setUp() public {
        orderInfoLib = new MockOrderInfoLib();
    }

    function testInvalidReactor() public {
        OrderInfo memory info = OrderInfoBuilder.init(address(0));

        vm.expectRevert(OrderInfoLib.InvalidReactor.selector);
        orderInfoLib.validate(info, address(0), mockResolvedOrder);
    }

    function testDeadlinePassed() public {
        uint256 timestamp = block.timestamp;
        vm.warp(timestamp + 100);
        OrderInfo memory info = OrderInfoBuilder.init(address(orderInfoLib)).withDeadline(block.timestamp - 1);

        vm.expectRevert(OrderInfoLib.DeadlinePassed.selector);
        orderInfoLib.validate(info, address(0), mockResolvedOrder);
    }

    function testValid() public view {
        orderInfoLib.validate(OrderInfoBuilder.init(address(orderInfoLib)), address(0), mockResolvedOrder);
    }

    function testValidationContractInvalid() public {
        MockValidationContract validationContract = new MockValidationContract();
        validationContract.setValid(false);
        vm.expectRevert(OrderInfoLib.ValidationFailed.selector);
        OrderInfo memory info =
            OrderInfoBuilder.init(address(orderInfoLib)).withValidationContract(address(validationContract));
        orderInfoLib.validate(info, address(0), mockResolvedOrder);
    }

    function testValidationContractValid() public {
        MockValidationContract validationContract = new MockValidationContract();
        validationContract.setValid(true);
        OrderInfo memory info =
            OrderInfoBuilder.init(address(orderInfoLib)).withValidationContract(address(validationContract));
        orderInfoLib.validate(info, address(0), mockResolvedOrder);
    }

    function testRfqValidationContractInvalidFiller() public {
        vm.warp(900);
        RfqValidationContract rfqValidationContract = new RfqValidationContract();
        OrderInfo memory info = OrderInfoBuilder.init(address(orderInfoLib)).withValidationContract(
            address(rfqValidationContract)
        ).withValidationData(abi.encode(address(0x123), 1000));
        vm.expectRevert(OrderInfoLib.ValidationFailed.selector);
        orderInfoLib.validate(info, address(0x234), mockResolvedOrder);
    }
}
