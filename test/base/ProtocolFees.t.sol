// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {Owned} from "solmate/src/auth/Owned.sol";
import {Test} from "forge-std/Test.sol";
import {InputToken, OutputToken, OrderInfo, ResolvedOrder} from "../../src/base/ReactorStructs.sol";
import {NATIVE} from "../../src/lib/CurrencyLibrary.sol";
import {ProtocolFees} from "../../src/base/ProtocolFees.sol";
import {ResolvedOrderLib} from "../../src/lib/ResolvedOrderLib.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {MockProtocolFees} from "../util/mock/MockProtocolFees.sol";
import {MockFeeController} from "../util/mock/MockFeeController.sol";

contract ProtocolFeesTest is Test {
    using OrderInfoBuilder for OrderInfo;
    using ResolvedOrderLib for OrderInfo;

    address constant INTERFACE_FEE_RECIPIENT = address(10);
    address constant PROTOCOL_FEE_OWNER = address(11);
    address constant RECIPIENT = address(12);
    // 50/50 split
    uint256 constant PROTOCOL_FEE_BPS = 5000;

    MockERC20 tokenIn;
    MockERC20 tokenOut;
    MockProtocolFees fees;
    MockFeeController feeController;

    function setUp() public {
        fees = new MockProtocolFees(PROTOCOL_FEE_OWNER);
        tokenIn = new MockERC20("Input", "IN", 18);
        tokenOut = new MockERC20("Output", "OUT", 18);
        feeController = new MockFeeController(RECIPIENT);
        vm.prank(PROTOCOL_FEE_OWNER);
        fees.setProtocolFeeController(address(feeController));
    }

    function testSetFeeController() public {
        assertEq(address(fees.feeController()), address(feeController));
        vm.prank(PROTOCOL_FEE_OWNER);
        fees.setProtocolFeeController(address(2));
        assertEq(address(fees.feeController()), address(2));
    }

    function testSetFeeControllerOnlyOwner() public {
        assertEq(address(fees.feeController()), address(feeController));
        vm.prank(address(1));
        vm.expectRevert("UNAUTHORIZED");
        fees.setProtocolFeeController(address(2));
        assertEq(address(fees.feeController()), address(feeController));
    }

    function testTakeFeesNoFees() public {
        ResolvedOrder[] memory orders = new ResolvedOrder[](1);
        orders[0] = createOrder(1 ether, false);

        assertEq(orders[0].outputs.length, 1);
        ResolvedOrder[] memory afterFees = fees.takeFees(orders);
        assertEq(afterFees[0].outputs.length, 1);
        assertEq(afterFees[0].outputs[0].token, orders[0].outputs[0].token);
        assertEq(afterFees[0].outputs[0].amount, orders[0].outputs[0].amount);
        assertEq(afterFees[0].outputs[0].recipient, orders[0].outputs[0].recipient);
    }

    function testTakeFees() public {
        ResolvedOrder[] memory orders = new ResolvedOrder[](1);
        orders[0] = createOrder(1 ether, false);
        uint256 feeBps = 3;
        feeController.setFee(address(tokenIn), address(tokenOut), feeBps);

        assertEq(orders[0].outputs.length, 1);
        ResolvedOrder[] memory afterFees = fees.takeFees(orders);
        assertEq(afterFees[0].outputs.length, 2);
        assertEq(afterFees[0].outputs[0].token, orders[0].outputs[0].token);
        assertEq(afterFees[0].outputs[0].amount, orders[0].outputs[0].amount);
        assertEq(afterFees[0].outputs[0].recipient, orders[0].outputs[0].recipient);
        assertEq(afterFees[0].outputs[1].token, orders[0].outputs[0].token);
        assertEq(afterFees[0].outputs[1].amount, orders[0].outputs[0].amount * feeBps / 10000);
        assertEq(afterFees[0].outputs[1].recipient, RECIPIENT);
    }

    function createOrder(uint256 amount, bool isEthOutput) private view returns (ResolvedOrder memory) {
        OutputToken[] memory outputs = new OutputToken[](1);
        address outputToken = isEthOutput ? NATIVE : address(tokenOut);
        outputs[0] = OutputToken(outputToken, amount, RECIPIENT);
        // outputs[1] = OutputToken(outputToken, amount, INTERFACE_FEE_RECIPIENT);
        return ResolvedOrder({
            info: OrderInfoBuilder.init(address(0)),
            input: InputToken(address(tokenIn), 1 ether, 1 ether),
            outputs: outputs,
            sig: hex"00",
            hash: bytes32(0)
        });
    }
}
