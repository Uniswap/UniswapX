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
import {MockFeeControllerDuplicates} from "../util/mock/MockFeeControllerDuplicates.sol";

contract ProtocolFeesTest is Test {
    using OrderInfoBuilder for OrderInfo;
    using ResolvedOrderLib for OrderInfo;

    address constant INTERFACE_FEE_RECIPIENT = address(10);
    address constant PROTOCOL_FEE_OWNER = address(11);
    address constant RECIPIENT = address(12);
    address constant SWAPPER = address(13);

    MockERC20 tokenIn;
    MockERC20 tokenOut;
    MockERC20 tokenOut2;
    MockProtocolFees fees;
    MockFeeController feeController;

    function setUp() public {
        fees = new MockProtocolFees(PROTOCOL_FEE_OWNER);
        tokenIn = new MockERC20("Input", "IN", 18);
        tokenOut = new MockERC20("Output", "OUT", 18);
        tokenOut2 = new MockERC20("Output2", "OUT", 18);
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
        ResolvedOrder memory order = createOrder(1 ether, false);

        assertEq(order.outputs.length, 1);
        ResolvedOrder memory afterFees = fees.takeFees(order);
        assertEq(afterFees.outputs.length, 1);
        assertEq(afterFees.outputs[0].token, order.outputs[0].token);
        assertEq(afterFees.outputs[0].amount, order.outputs[0].amount);
        assertEq(afterFees.outputs[0].recipient, order.outputs[0].recipient);
    }

    function testTakeFees() public {
        ResolvedOrder memory order = createOrder(1 ether, false);
        uint256 feeBps = 3;
        feeController.setFee(address(tokenIn), address(tokenOut), feeBps);

        assertEq(order.outputs.length, 1);
        ResolvedOrder memory afterFees = fees.takeFees(order);
        assertEq(afterFees.outputs.length, 2);
        assertEq(afterFees.outputs[0].token, order.outputs[0].token);
        assertEq(afterFees.outputs[0].amount, order.outputs[0].amount);
        assertEq(afterFees.outputs[0].recipient, order.outputs[0].recipient);
        assertEq(afterFees.outputs[1].token, order.outputs[0].token);
        assertEq(afterFees.outputs[1].amount, order.outputs[0].amount * feeBps / 10000);
        assertEq(afterFees.outputs[1].recipient, RECIPIENT);
    }

    function testTakeFeesFuzzOutputs(uint128 inputAmount, uint128[] memory outputAmounts, uint256 feeBps) public {
        vm.assume(feeBps <= 5);
        OutputToken[] memory outputs = new OutputToken[](outputAmounts.length);
        for (uint256 i = 0; i < outputAmounts.length; i++) {
            outputs[i] = OutputToken(address(tokenOut), outputAmounts[i], RECIPIENT);
        }
        ResolvedOrder memory order = ResolvedOrder({
            info: OrderInfoBuilder.init(address(0)),
            input: InputToken(address(tokenIn), inputAmount, inputAmount),
            outputs: outputs,
            sig: hex"00",
            hash: bytes32(0)
        });
        for (uint256 i = 0; i < outputs.length; i++) {
            feeController.setFee(address(tokenIn), address(outputs[i].token), feeBps);
        }

        ResolvedOrder memory afterFees = fees.takeFees(order);
        assertGe(afterFees.outputs.length, outputs.length);

        for (uint256 i = 0; i < outputAmounts.length; i++) {
            address tokenAddress = order.outputs[i].token;
            uint256 baseAmount = order.outputs[i].amount;

            uint256 extraOutputs = afterFees.outputs.length - outputAmounts.length;
            for (uint256 j = 0; j < extraOutputs; j++) {
                OutputToken memory output = afterFees.outputs[outputAmounts.length + j];
                if (output.token == tokenAddress) {
                    assertGe(output.amount, baseAmount * feeBps / 10000);
                }
            }
        }
    }

    function testTakeFeesWithInterfaceFee() public {
        ResolvedOrder memory order = createOrderWithInterfaceFee(1 ether, false);
        uint256 feeBps = 3;
        feeController.setFee(address(tokenIn), address(tokenOut), feeBps);

        assertEq(order.outputs.length, 2);
        ResolvedOrder memory afterFees = fees.takeFees(order);
        assertEq(afterFees.outputs.length, 3);
        assertEq(afterFees.outputs[0].token, order.outputs[0].token);
        assertEq(afterFees.outputs[0].amount, order.outputs[0].amount);
        assertEq(afterFees.outputs[0].recipient, order.outputs[0].recipient);
        assertEq(afterFees.outputs[1].token, order.outputs[1].token);
        assertEq(afterFees.outputs[1].amount, order.outputs[1].amount);
        assertEq(afterFees.outputs[1].recipient, order.outputs[1].recipient);
        assertEq(afterFees.outputs[2].token, order.outputs[1].token);
        assertEq(afterFees.outputs[2].amount, (order.outputs[1].amount + order.outputs[1].amount) * feeBps / 10000);
        assertEq(afterFees.outputs[2].recipient, RECIPIENT);
    }

    function testTakeFeesTooMuch() public {
        ResolvedOrder memory order = createOrderWithInterfaceFee(1 ether, false);
        uint256 feeBps = 10;
        feeController.setFee(address(tokenIn), address(tokenOut), feeBps);

        vm.expectRevert(ProtocolFees.FeeTooLarge.selector);
        fees.takeFees(order);
    }

    function testTakeFeesDuplicate() public {
        MockFeeControllerDuplicates controller = new MockFeeControllerDuplicates(RECIPIENT);
        vm.prank(PROTOCOL_FEE_OWNER);
        fees.setProtocolFeeController(address(controller));

        ResolvedOrder memory order = createOrderWithInterfaceFee(1 ether, false);
        uint256 feeBps = 10;
        controller.setFee(address(tokenIn), address(tokenOut), feeBps);

        vm.expectRevert(ProtocolFees.DuplicateFeeOutput.selector);
        fees.takeFees(order);
    }

    // The order contains 2 outputs: 1 tokenOut to SWAPPER and 2 tokenOut2 to SWAPPER
    function testTakeFeesMultipleOutputTokens() public {
        OutputToken[] memory outputs = new OutputToken[](2);
        outputs[0] = OutputToken(address(tokenOut), 1 ether, SWAPPER);
        outputs[1] = OutputToken(address(tokenOut2), 2 ether, SWAPPER);
        ResolvedOrder memory order = ResolvedOrder({
            info: OrderInfoBuilder.init(address(0)),
            input: InputToken(address(tokenIn), 1 ether, 1 ether),
            outputs: outputs,
            sig: hex"00",
            hash: bytes32(0)
        });
        feeController.setFee(address(tokenIn), address(tokenOut), 4);
        feeController.setFee(address(tokenIn), address(tokenOut2), 3);

        ResolvedOrder memory afterFees = fees.takeFees(order);
        assertEq(afterFees.outputs.length, 4);
        assertEq(afterFees.outputs[0].token, address(tokenOut));
        assertEq(afterFees.outputs[0].amount, 1 ether);
        assertEq(afterFees.outputs[0].recipient, SWAPPER);
        assertEq(afterFees.outputs[1].token, address(tokenOut2));
        assertEq(afterFees.outputs[1].amount, 2 ether);
        assertEq(afterFees.outputs[1].recipient, SWAPPER);
        assertEq(afterFees.outputs[2].token, address(tokenOut));
        assertEq(afterFees.outputs[2].amount, 1 ether * 4 / 10000);
        assertEq(afterFees.outputs[2].recipient, RECIPIENT);
        assertEq(afterFees.outputs[3].token, address(tokenOut2));
        assertEq(afterFees.outputs[3].amount, 2 ether * 3 / 10000);
        assertEq(afterFees.outputs[3].recipient, RECIPIENT);
    }

    // The order contains 4 outputs:
    // 1 tokenOut to SWAPPER
    // 0.05 tokenOut to INTERFACE_FEE_RECIPIENT
    // 2 tokenOut2 to SWAPPER
    // 0.1 tokenOut2 to INTERFACE_FEE_RECIPIENT
    // There will only be protocol fee enabled for tokenOut2
    function testTakeFeesMultipleOutputTokensWithInterfaceFee() public {
        OutputToken[] memory outputs = new OutputToken[](4);
        outputs[0] = OutputToken(address(tokenOut), 1 ether, SWAPPER);
        outputs[1] = OutputToken(address(tokenOut), 1 ether / 20, INTERFACE_FEE_RECIPIENT);
        outputs[2] = OutputToken(address(tokenOut2), 2 ether, SWAPPER);
        outputs[3] = OutputToken(address(tokenOut2), 2 ether / 20, INTERFACE_FEE_RECIPIENT);
        ResolvedOrder memory order = ResolvedOrder({
            info: OrderInfoBuilder.init(address(0)),
            input: InputToken(address(tokenIn), 1 ether, 1 ether),
            outputs: outputs,
            sig: hex"00",
            hash: bytes32(0)
        });
        feeController.setFee(address(tokenIn), address(tokenOut2), 3);

        ResolvedOrder memory afterFees = fees.takeFees(order);
        assertEq(afterFees.outputs.length, 5);
        assertEq(afterFees.outputs[0].token, address(tokenOut));
        assertEq(afterFees.outputs[0].amount, 1 ether);
        assertEq(afterFees.outputs[0].recipient, SWAPPER);
        assertEq(afterFees.outputs[1].token, address(tokenOut));
        assertEq(afterFees.outputs[1].amount, 1 ether / 20);
        assertEq(afterFees.outputs[1].recipient, INTERFACE_FEE_RECIPIENT);
        assertEq(afterFees.outputs[2].token, address(tokenOut2));
        assertEq(afterFees.outputs[2].amount, 2 ether);
        assertEq(afterFees.outputs[2].recipient, SWAPPER);
        assertEq(afterFees.outputs[3].token, address(tokenOut2));
        assertEq(afterFees.outputs[3].amount, 2 ether / 20);
        assertEq(afterFees.outputs[3].recipient, INTERFACE_FEE_RECIPIENT);
        assertEq(afterFees.outputs[4].token, address(tokenOut2));
        assertEq(afterFees.outputs[4].amount, 2 ether * 21 / 20 * 3 / 10000);
        assertEq(afterFees.outputs[4].recipient, RECIPIENT);
    }

    function createOrder(uint256 amount, bool isEthOutput) private view returns (ResolvedOrder memory) {
        OutputToken[] memory outputs = new OutputToken[](1);
        address outputToken = isEthOutput ? NATIVE : address(tokenOut);
        outputs[0] = OutputToken(outputToken, amount, RECIPIENT);
        return ResolvedOrder({
            info: OrderInfoBuilder.init(address(0)),
            input: InputToken(address(tokenIn), 1 ether, 1 ether),
            outputs: outputs,
            sig: hex"00",
            hash: bytes32(0)
        });
    }

    function createOrderWithInterfaceFee(uint256 amount, bool isEthOutput)
        private
        view
        returns (ResolvedOrder memory)
    {
        OutputToken[] memory outputs = new OutputToken[](2);
        address outputToken = isEthOutput ? NATIVE : address(tokenOut);
        outputs[0] = OutputToken(outputToken, amount, RECIPIENT);
        outputs[1] = OutputToken(outputToken, amount, INTERFACE_FEE_RECIPIENT);
        return ResolvedOrder({
            info: OrderInfoBuilder.init(address(0)),
            input: InputToken(address(tokenIn), 1 ether, 1 ether),
            outputs: outputs,
            sig: hex"00",
            hash: bytes32(0)
        });
    }
}
