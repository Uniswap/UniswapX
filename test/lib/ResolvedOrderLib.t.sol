// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {OrderInfo, ResolvedOrder} from "../../src/base/ReactorStructs.sol";
import {ResolvedOrderLib} from "../../src/lib/ResolvedOrderLib.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {MockResolvedOrderLib} from "../util/mock/MockResolvedOrderLib.sol";
import {MockPreparationContract} from "../util/mock/MockPreparationContract.sol";
import {ExclusiveFillerPreparation} from "../../src/sample-preparation-contracts/ExclusiveFillerPreparation.sol";

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
        resolvedOrderLib.prepare(mockResolvedOrder, address(0));
    }

    function testDeadlinePassed() public {
        uint256 timestamp = block.timestamp;
        vm.warp(timestamp + 100);
        mockResolvedOrder.info = OrderInfoBuilder.init(address(resolvedOrderLib)).withDeadline(block.timestamp - 1);

        vm.expectRevert(ResolvedOrderLib.DeadlinePassed.selector);
        resolvedOrderLib.prepare(mockResolvedOrder, address(0));
    }

    function testValid() public {
        mockResolvedOrder.info = OrderInfoBuilder.init(address(resolvedOrderLib));
        resolvedOrderLib.prepare(mockResolvedOrder, address(0));
    }

    function testpreparationContractInvalid() public {
        MockPreparationContract preparationContract = new MockPreparationContract();
        preparationContract.setValid(false);
        vm.expectRevert(MockPreparationContract.ValidationFailed.selector);
        mockResolvedOrder.info =
            OrderInfoBuilder.init(address(resolvedOrderLib)).withPreparationContract(address(preparationContract));
        resolvedOrderLib.prepare(mockResolvedOrder, address(0));
    }

    function testpreparationContractValid() public {
        MockPreparationContract preparationContract = new MockPreparationContract();
        preparationContract.setValid(true);
        mockResolvedOrder.info =
            OrderInfoBuilder.init(address(resolvedOrderLib)).withPreparationContract(address(preparationContract));
        resolvedOrderLib.prepare(mockResolvedOrder, address(0));
    }

    function testExclusiveFillerPreparationInvalidFiller() public {
        vm.warp(900);
        ExclusiveFillerPreparation prep = new ExclusiveFillerPreparation();
        mockResolvedOrder.info = OrderInfoBuilder.init(address(resolvedOrderLib)).withPreparationContract(
            address(prep)
        ).withPreparationData(abi.encode(address(0x123), 1000, 0));
        vm.expectRevert(MockPreparationContract.ValidationFailed.selector);
        resolvedOrderLib.prepare(mockResolvedOrder, address(0x234));
    }

    // The filler is not the same filler as the filler encoded in preparationData, but we are past the last
    // exclusive timestamp, so it will not revert.
    function testExclusiveFillerPreparationInvalidFillerPastTimestamp() public {
        vm.warp(900);
        ExclusiveFillerPreparation prep = new ExclusiveFillerPreparation();
        mockResolvedOrder.info = OrderInfoBuilder.init(address(resolvedOrderLib)).withPreparationContract(
            address(prep)
        ).withPreparationData(abi.encode(address(0x123), 888, 0));
        resolvedOrderLib.prepare(mockResolvedOrder, address(0x234));
    }

    // Kind of a pointless test, but ensure the specified filler can fill after last exclusive timestamp still.
    function testExclusiveFillerPreparationValidFillerPastTimestamp() public {
        vm.warp(900);
        ExclusiveFillerPreparation prep = new ExclusiveFillerPreparation();
        mockResolvedOrder.info = OrderInfoBuilder.init(address(resolvedOrderLib)).withPreparationContract(
            address(prep)
        ).withPreparationData(abi.encode(address(0x123), 1000, 0));
        resolvedOrderLib.prepare(mockResolvedOrder, address(0x123));
    }
}
