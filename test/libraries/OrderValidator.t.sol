// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {OrderInfo} from "../../src/interfaces/ReactorStructs.sol";
import {OrderValidator} from "../../src/lib/OrderValidator.sol";
import {MockValidationContract} from "../../src/test/MockValidationContract.sol";

contract OrderValidatorTest is Test {
    OrderValidator validator;

    function setUp() public {
        validator = new OrderValidator();
    }

    function testInvalidReactor() public {
        vm.expectRevert(OrderValidator.InvalidReactor.selector);
        validator.validateOrder(
            OrderInfo({
                reactor: address(0),
                offerer: address(1),
                validationContract: address(0),
                validationData: bytes(""),
                counter: 0,
                deadline: block.timestamp
            })
        );
    }

    function testDeadlinePassed() public {
        vm.expectRevert(OrderValidator.DeadlinePassed.selector);
        uint256 timestamp = block.timestamp;
        vm.warp(timestamp + 100);
        validator.validateOrder(
            OrderInfo({
                reactor: address(validator),
                offerer: address(1),
                validationContract: address(0),
                validationData: bytes(""),
                counter: 0,
                deadline: timestamp
            })
        );
    }

    function testValidationContractInvalid() public {
        MockValidationContract validationContract = new MockValidationContract();
        validationContract.setValid(false);
        vm.expectRevert(OrderValidator.InvalidOrder.selector);
        validator.validateOrder(
            OrderInfo({
                reactor: address(validator),
                offerer: address(1),
                validationContract: address(validationContract),
                validationData: bytes(""),
                counter: 0,
                deadline: block.timestamp
            })
        );
    }

    function testValid() public view {
        validator.validateOrder(
            OrderInfo({
                reactor: address(validator),
                offerer: address(1),
                validationContract: address(0),
                validationData: bytes(""),
                counter: 0,
                deadline: block.timestamp
            })
        );
    }

    function testValidationContractValid() public {
        MockValidationContract validationContract = new MockValidationContract();
        validationContract.setValid(true);
        validator.validateOrder(
            OrderInfo({
                reactor: address(validator),
                offerer: address(1),
                validationContract: address(validationContract),
                validationData: bytes(""),
                counter: 0,
                deadline: block.timestamp
            })
        );
    }
}
