// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Owned} from "solmate/src/auth/Owned.sol";
import {Test} from "forge-std/Test.sol";
import {InputToken, OutputToken, OrderInfo, ResolvedOrder, SignedOrder} from "../../src/base/ReactorStructs.sol";
import {NATIVE} from "../../src/lib/CurrencyLibrary.sol";
import {ProtocolFees} from "../../src/base/ProtocolFees.sol";
import {ResolvedOrderLib} from "../../src/lib/ResolvedOrderLib.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {MockProtocolFees} from "../util/mock/MockProtocolFees.sol";
import {MockFeeController} from "../util/mock/MockFeeController.sol";
import {MockFeeControllerDuplicates} from "../util/mock/MockFeeControllerDuplicates.sol";
import {MockFeeControllerZeroFee} from "../util/mock/MockFeeControllerZeroFee.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {DeployPermit2} from "../util/DeployPermit2.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {MockFillContract} from "../util/mock/MockFillContract.sol";
import {MockFeeController} from "../util/mock/MockFeeController.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {
    ExclusiveDutchOrderReactor,
    ExclusiveDutchOrder,
    DutchInput,
    DutchOutput
} from "../../src/reactors/ExclusiveDutchOrderReactor.sol";

contract ProtocolFeesTest is Test {
    using OrderInfoBuilder for OrderInfo;
    using ResolvedOrderLib for OrderInfo;

    event ProtocolFeeControllerSet(address oldFeeController, address newFeeController);

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
        vm.expectEmit(true, true, false, false);
        emit ProtocolFeeControllerSet(address(feeController), address(2));

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
        feeController.setFee(tokenIn, address(tokenOut), feeBps);

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
        vm.assume(outputAmounts.length > 0);
        OutputToken[] memory outputs = new OutputToken[](outputAmounts.length);
        for (uint256 i = 0; i < outputAmounts.length; i++) {
            outputs[i] = OutputToken(address(tokenOut), outputAmounts[i], RECIPIENT);
        }
        ResolvedOrder memory order = ResolvedOrder({
            info: OrderInfoBuilder.init(address(0)),
            input: InputToken(tokenIn, inputAmount, inputAmount),
            outputs: outputs,
            sig: hex"00",
            hash: bytes32(0)
        });
        feeController.setFee(tokenIn, address(outputs[0].token), feeBps);

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
        feeController.setFee(tokenIn, address(tokenOut), feeBps);

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
        feeController.setFee(tokenIn, address(tokenOut), feeBps);

        vm.expectRevert(
            abi.encodeWithSelector(
                ProtocolFees.FeeTooLarge.selector,
                address(tokenOut),
                order.outputs[0].amount * 2 * 10 / 10000,
                RECIPIENT
            )
        );
        fees.takeFees(order);
    }

    function testTakeFeesDuplicate() public {
        MockFeeControllerDuplicates controller = new MockFeeControllerDuplicates(RECIPIENT);
        vm.prank(PROTOCOL_FEE_OWNER);
        fees.setProtocolFeeController(address(controller));

        ResolvedOrder memory order = createOrderWithInterfaceFee(1 ether, false);
        uint256 feeBps = 10;
        controller.setFee(tokenIn, address(tokenOut), feeBps);

        vm.expectRevert(abi.encodeWithSelector(ProtocolFees.DuplicateFeeOutput.selector, tokenOut));
        fees.takeFees(order);
    }

    // The order contains 2 outputs: 1 tokenOut to SWAPPER and 2 tokenOut2 to SWAPPER
    function testTakeFeesMultipleOutputTokens() public {
        OutputToken[] memory outputs = new OutputToken[](2);
        outputs[0] = OutputToken(address(tokenOut), 1 ether, SWAPPER);
        outputs[1] = OutputToken(address(tokenOut2), 2 ether, SWAPPER);
        ResolvedOrder memory order = ResolvedOrder({
            info: OrderInfoBuilder.init(address(0)),
            input: InputToken(tokenIn, 1 ether, 1 ether),
            outputs: outputs,
            sig: hex"00",
            hash: bytes32(0)
        });
        feeController.setFee(tokenIn, address(tokenOut), 4);
        feeController.setFee(tokenIn, address(tokenOut2), 3);

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
            input: InputToken(tokenIn, 1 ether, 1 ether),
            outputs: outputs,
            sig: hex"00",
            hash: bytes32(0)
        });
        feeController.setFee(tokenIn, address(tokenOut2), 3);

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

    // The same as testTakeFeesMultipleOutputTokensWithInterfaceFee but change the order of some outputs
    // The order contains 4 outputs:
    // 0.1 tokenOut2 to INTERFACE_FEE_RECIPIENT
    // 1 tokenOut to SWAPPER
    // 2 tokenOut2 to SWAPPER
    // 0.05 tokenOut to INTERFACE_FEE_RECIPIENT
    // There will only be protocol fee enabled for tokenOut2
    function testTakeFeesMultipleOutputTokensWithInterfaceFeeChangeOrder() public {
        OutputToken[] memory outputs = new OutputToken[](4);
        outputs[0] = OutputToken(address(tokenOut2), 2 ether / 20, INTERFACE_FEE_RECIPIENT);
        outputs[1] = OutputToken(address(tokenOut), 1 ether, SWAPPER);
        outputs[2] = OutputToken(address(tokenOut2), 2 ether, SWAPPER);
        outputs[3] = OutputToken(address(tokenOut), 1 ether / 20, INTERFACE_FEE_RECIPIENT);
        ResolvedOrder memory order = ResolvedOrder({
            info: OrderInfoBuilder.init(address(0)),
            input: InputToken(tokenIn, 1 ether, 1 ether),
            outputs: outputs,
            sig: hex"00",
            hash: bytes32(0)
        });
        feeController.setFee(tokenIn, address(tokenOut2), 3);

        ResolvedOrder memory afterFees = fees.takeFees(order);
        assertEq(afterFees.outputs.length, 5);
        assertEq(afterFees.outputs[0].token, address(tokenOut2));
        assertEq(afterFees.outputs[0].amount, 2 ether / 20);
        assertEq(afterFees.outputs[0].recipient, INTERFACE_FEE_RECIPIENT);
        assertEq(afterFees.outputs[1].token, address(tokenOut));
        assertEq(afterFees.outputs[2].token, address(tokenOut2));
        assertEq(afterFees.outputs[2].amount, 2 ether);
        assertEq(afterFees.outputs[2].recipient, SWAPPER);
        assertEq(afterFees.outputs[1].amount, 1 ether);
        assertEq(afterFees.outputs[1].recipient, SWAPPER);
        assertEq(afterFees.outputs[3].token, address(tokenOut));
        assertEq(afterFees.outputs[3].amount, 1 ether / 20);
        assertEq(afterFees.outputs[3].recipient, INTERFACE_FEE_RECIPIENT);
        assertEq(afterFees.outputs[4].token, address(tokenOut2));
        assertEq(afterFees.outputs[4].amount, 2 ether * 21 / 20 * 3 / 10000);
        assertEq(afterFees.outputs[4].recipient, RECIPIENT);
    }

    // The same as testTakeFeesMultipleOutputTokensWithInterfaceFee but enable fees for tokenOut as well
    function testTakeFeesMultipleOutputTokensWithInterfaceFeeBothFees() public {
        OutputToken[] memory outputs = new OutputToken[](4);
        outputs[0] = OutputToken(address(tokenOut), 1 ether, SWAPPER);
        outputs[1] = OutputToken(address(tokenOut), 1 ether / 20, INTERFACE_FEE_RECIPIENT);
        outputs[2] = OutputToken(address(tokenOut2), 2 ether, SWAPPER);
        outputs[3] = OutputToken(address(tokenOut2), 2 ether / 20, INTERFACE_FEE_RECIPIENT);
        ResolvedOrder memory order = ResolvedOrder({
            info: OrderInfoBuilder.init(address(0)),
            input: InputToken(tokenIn, 1 ether, 1 ether),
            outputs: outputs,
            sig: hex"00",
            hash: bytes32(0)
        });
        feeController.setFee(tokenIn, address(tokenOut), 5);
        feeController.setFee(tokenIn, address(tokenOut2), 3);

        ResolvedOrder memory afterFees = fees.takeFees(order);
        assertEq(afterFees.outputs.length, 6);
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
        assertEq(afterFees.outputs[4].token, address(tokenOut));
        assertEq(afterFees.outputs[4].amount, 1 ether * 21 / 20 * 5 / 10000);
        assertEq(afterFees.outputs[4].recipient, RECIPIENT);
        assertEq(afterFees.outputs[5].token, address(tokenOut2));
        assertEq(afterFees.outputs[5].amount, 2 ether * 21 / 20 * 3 / 10000);
        assertEq(afterFees.outputs[5].recipient, RECIPIENT);
    }

    // The same as testTakeFeesMultipleOutputTokensWithInterfaceFeeBothFees but change the order of outputs
    function testTakeFeesMultipleOutputTokensWithInterfaceFeeBothFeesChangeOrder() public {
        OutputToken[] memory outputs = new OutputToken[](4);
        outputs[3] = OutputToken(address(tokenOut), 1 ether, SWAPPER);
        outputs[1] = OutputToken(address(tokenOut), 1 ether / 20, INTERFACE_FEE_RECIPIENT);
        outputs[2] = OutputToken(address(tokenOut2), 2 ether, SWAPPER);
        outputs[0] = OutputToken(address(tokenOut2), 2 ether / 20, INTERFACE_FEE_RECIPIENT);
        ResolvedOrder memory order = ResolvedOrder({
            info: OrderInfoBuilder.init(address(0)),
            input: InputToken(tokenIn, 1 ether, 1 ether),
            outputs: outputs,
            sig: hex"00",
            hash: bytes32(0)
        });
        feeController.setFee(tokenIn, address(tokenOut), 5);
        feeController.setFee(tokenIn, address(tokenOut2), 3);

        ResolvedOrder memory afterFees = fees.takeFees(order);
        assertEq(afterFees.outputs.length, 6);
        assertEq(afterFees.outputs[3].token, address(tokenOut));
        assertEq(afterFees.outputs[3].amount, 1 ether);
        assertEq(afterFees.outputs[3].recipient, SWAPPER);
        assertEq(afterFees.outputs[1].token, address(tokenOut));
        assertEq(afterFees.outputs[1].amount, 1 ether / 20);
        assertEq(afterFees.outputs[1].recipient, INTERFACE_FEE_RECIPIENT);
        assertEq(afterFees.outputs[2].token, address(tokenOut2));
        assertEq(afterFees.outputs[2].amount, 2 ether);
        assertEq(afterFees.outputs[2].recipient, SWAPPER);
        assertEq(afterFees.outputs[0].token, address(tokenOut2));
        assertEq(afterFees.outputs[0].amount, 2 ether / 20);
        assertEq(afterFees.outputs[0].recipient, INTERFACE_FEE_RECIPIENT);
        assertEq(afterFees.outputs[5].token, address(tokenOut));
        assertEq(afterFees.outputs[5].amount, 1 ether * 21 / 20 * 5 / 10000);
        assertEq(afterFees.outputs[5].recipient, RECIPIENT);
        assertEq(afterFees.outputs[4].token, address(tokenOut2));
        assertEq(afterFees.outputs[4].amount, 2 ether * 21 / 20 * 3 / 10000);
        assertEq(afterFees.outputs[4].recipient, RECIPIENT);
    }

    function testTakeFeesInvalidFeeToken() public {
        MockFeeControllerZeroFee controller = new MockFeeControllerZeroFee(RECIPIENT);
        vm.prank(PROTOCOL_FEE_OWNER);
        fees.setProtocolFeeController(address(controller));

        ResolvedOrder memory order = createOrderWithInterfaceFee(1 ether, false);
        uint256 feeBps = 5;
        controller.setFee(tokenIn, address(tokenOut), feeBps);

        vm.expectRevert(abi.encodeWithSelector(ProtocolFees.InvalidFeeToken.selector, address(0)));
        fees.takeFees(order);
    }

    function createOrder(uint256 amount, bool isEthOutput) private view returns (ResolvedOrder memory) {
        OutputToken[] memory outputs = new OutputToken[](1);
        address outputToken = isEthOutput ? NATIVE : address(tokenOut);
        outputs[0] = OutputToken(outputToken, amount, SWAPPER);
        return ResolvedOrder({
            info: OrderInfoBuilder.init(address(0)),
            input: InputToken(tokenIn, 1 ether, 1 ether),
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
            input: InputToken(tokenIn, 1 ether, 1 ether),
            outputs: outputs,
            sig: hex"00",
            hash: bytes32(0)
        });
    }
}

// The purpose of ProtocolFeesGasComparisonTest is to see how much gas increases when interface and/or
// protocol fees are added.
contract ProtocolFeesGasComparisonTest is Test, PermitSignature, DeployPermit2, GasSnapshot {
    using OrderInfoBuilder for OrderInfo;

    address constant PROTOCOL_FEE_OWNER = address(1001);
    address constant INTERFACE_FEE_RECIPIENT = address(1002);
    address constant PROTOCOL_FEE_RECIPIENT = address(1003);

    MockERC20 tokenIn1;
    MockERC20 tokenOut1;
    uint256 swapperPrivateKey1;
    address swapper1;
    ExclusiveDutchOrderReactor reactor;
    IPermit2 permit2;
    MockFillContract fillContract;
    MockFeeController feeController;

    function setUp() public {
        tokenIn1 = new MockERC20("tokenIn1", "IN1", 18);
        tokenOut1 = new MockERC20("tokenOut1", "OUT1", 18);
        swapperPrivateKey1 = 0x12341234;
        swapper1 = vm.addr(swapperPrivateKey1);

        feeController = new MockFeeController(PROTOCOL_FEE_RECIPIENT);
        permit2 = IPermit2(deployPermit2());
        reactor = new ExclusiveDutchOrderReactor(permit2, PROTOCOL_FEE_OWNER);
        fillContract = new MockFillContract(address(reactor));
        vm.prank(PROTOCOL_FEE_OWNER);
        reactor.setProtocolFeeController(address(feeController));

        tokenIn1.forceApprove(swapper1, address(permit2), type(uint256).max);
        // Keep non 0 balances in swapper1, INTERFACE_FEE_RECIPIENT, PROTOCOL_FEE_RECIPIENT to simulate best
        // case gas scenario
        tokenOut1.mint(swapper1, 1 ether);
        tokenOut1.mint(INTERFACE_FEE_RECIPIENT, 1 ether);
        tokenOut1.mint(PROTOCOL_FEE_RECIPIENT, 1 ether);
        tokenIn1.mint(address(fillContract), 1 ether);
        vm.deal(swapper1, 1 ether);
        vm.deal(INTERFACE_FEE_RECIPIENT, 1 ether);
        vm.deal(PROTOCOL_FEE_RECIPIENT, 1 ether);
    }

    // Fill an order without fees: input = 1 tokenIn, output = 1 tokenOut
    function testNoFees() public {
        tokenIn1.mint(swapper1, 1 ether);
        tokenOut1.mint(address(fillContract), 1 ether);

        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(tokenOut1), 1 ether, 1 ether, swapper1);
        ExclusiveDutchOrder memory order = ExclusiveDutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper1).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 0,
            input: DutchInput(tokenIn1, 1 ether, 1 ether),
            outputs: dutchOutputs
        });
        snapStart("ProtocolFeesGasComparisonTest-NoFees");
        fillContract.execute(SignedOrder(abi.encode(order), signOrder(swapperPrivateKey1, address(permit2), order)));
        snapEnd();
        assertEq(tokenIn1.balanceOf(address(fillContract)), 2 ether);
        assertEq(tokenOut1.balanceOf(address(swapper1)), 2 ether);
    }

    // Fill an order with an interface fee: input = 1 tokenIn, output = [1 tokenOut to swapper1, 0.05 tokenOut to interface]
    function testInterfaceFee() public {
        tokenIn1.mint(address(swapper1), 1 ether);
        tokenOut1.mint(address(fillContract), 2 ether);

        DutchOutput[] memory dutchOutputs = new DutchOutput[](2);
        dutchOutputs[0] = DutchOutput(address(tokenOut1), 1 ether, 1 ether, swapper1);
        dutchOutputs[1] = DutchOutput(address(tokenOut1), 1 ether / 20, 1 ether / 20, INTERFACE_FEE_RECIPIENT);
        ExclusiveDutchOrder memory order = ExclusiveDutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper1).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 0,
            input: DutchInput(tokenIn1, 1 ether, 1 ether),
            outputs: dutchOutputs
        });
        snapStart("ProtocolFeesGasComparisonTest-InterfaceFee");
        fillContract.execute(SignedOrder(abi.encode(order), signOrder(swapperPrivateKey1, address(permit2), order)));
        snapEnd();
        assertEq(tokenIn1.balanceOf(address(fillContract)), 2 ether);
        assertEq(tokenOut1.balanceOf(address(swapper1)), 2 ether);
        assertEq(tokenOut1.balanceOf(address(INTERFACE_FEE_RECIPIENT)), 21 ether / 20);
    }

    // Fill an order with an interface fee and protocol fee: input = 1 tokenIn,
    // output = [1 tokenOut to swapper1, 0.05 tokenOut to interface]. Protocol fee = 5bps
    function testInterfaceAndProtocolFee() public {
        feeController.setFee(tokenIn1, address(tokenOut1), 5);

        tokenIn1.mint(address(swapper1), 1 ether);
        tokenOut1.mint(address(fillContract), 2 ether);

        DutchOutput[] memory dutchOutputs = new DutchOutput[](2);
        dutchOutputs[0] = DutchOutput(address(tokenOut1), 1 ether, 1 ether, swapper1);
        dutchOutputs[1] = DutchOutput(address(tokenOut1), 1 ether / 20, 1 ether / 20, INTERFACE_FEE_RECIPIENT);
        ExclusiveDutchOrder memory order = ExclusiveDutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper1).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 0,
            input: DutchInput(tokenIn1, 1 ether, 1 ether),
            outputs: dutchOutputs
        });
        snapStart("ProtocolFeesGasComparisonTest-InterfaceAndProtocolFee");
        fillContract.execute(SignedOrder(abi.encode(order), signOrder(swapperPrivateKey1, address(permit2), order)));
        snapEnd();
        // fillContract had 1 tokenIn1 preminted to it
        assertEq(tokenIn1.balanceOf(address(fillContract)), 2 ether);
        // swapper had 1 tokenOut1 preminted to it
        assertEq(tokenOut1.balanceOf(swapper1), 2 ether);
        // INTERFACE_FEE_RECIPIENT had 1 tokenOut1 preminted to it
        assertEq(tokenOut1.balanceOf(INTERFACE_FEE_RECIPIENT), 21 ether / 20);
        // Protocol fee is 5 bps * 1.05
        assertEq(tokenOut1.balanceOf(PROTOCOL_FEE_RECIPIENT), 1 ether + 21 ether / 20 * 5 / 10000);
    }

    // The same as `testNoFees`, but output = 1 ether
    function testNoFeesEthOutput() public {
        tokenIn1.mint(swapper1, 1 ether);
        vm.deal(address(fillContract), 1 ether);

        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(NATIVE, 1 ether, 1 ether, swapper1);
        ExclusiveDutchOrder memory order = ExclusiveDutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper1).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 0,
            input: DutchInput(tokenIn1, 1 ether, 1 ether),
            outputs: dutchOutputs
        });
        snapStart("ProtocolFeesGasComparisonTest-NoFeesEthOutput");
        fillContract.execute(SignedOrder(abi.encode(order), signOrder(swapperPrivateKey1, address(permit2), order)));
        snapEnd();
        assertEq(tokenIn1.balanceOf(address(fillContract)), 2 ether);
        assertEq(swapper1.balance, 2 ether);
    }

    // Fill an order with an interface fee: input = 1 tokenIn, output = [1 ether to swapper1, 0.05 ether to interface]
    function testInterfaceFeeEthOutput() public {
        tokenIn1.mint(address(swapper1), 1 ether);
        vm.deal(address(fillContract), 2 ether);

        DutchOutput[] memory dutchOutputs = new DutchOutput[](2);
        dutchOutputs[0] = DutchOutput(NATIVE, 1 ether, 1 ether, swapper1);
        dutchOutputs[1] = DutchOutput(NATIVE, 1 ether / 20, 1 ether / 20, INTERFACE_FEE_RECIPIENT);
        ExclusiveDutchOrder memory order = ExclusiveDutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper1).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 0,
            input: DutchInput(tokenIn1, 1 ether, 1 ether),
            outputs: dutchOutputs
        });
        snapStart("ProtocolFeesGasComparisonTest-InterfaceFeeEthOutput");
        fillContract.execute(SignedOrder(abi.encode(order), signOrder(swapperPrivateKey1, address(permit2), order)));
        snapEnd();
        assertEq(tokenIn1.balanceOf(address(fillContract)), 2 ether);
        assertEq(swapper1.balance, 2 ether);
        assertEq(INTERFACE_FEE_RECIPIENT.balance, 21 ether / 20);
    }

    // Fill an order with an interface fee and protocol fee: input = 1 tokenIn,
    // output = [1 ether to swapper1, 0.05 ether to interface]. Protocol fee = 5bps
    function testInterfaceAndProtocolFeeEthOutput() public {
        feeController.setFee(tokenIn1, NATIVE, 5);

        tokenIn1.mint(address(swapper1), 1 ether);
        vm.deal(address(fillContract), 2 ether);

        DutchOutput[] memory dutchOutputs = new DutchOutput[](2);
        dutchOutputs[0] = DutchOutput(NATIVE, 1 ether, 1 ether, swapper1);
        dutchOutputs[1] = DutchOutput(NATIVE, 1 ether / 20, 1 ether / 20, INTERFACE_FEE_RECIPIENT);
        ExclusiveDutchOrder memory order = ExclusiveDutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper1).withDeadline(block.timestamp + 100),
            decayStartTime: block.timestamp,
            decayEndTime: block.timestamp + 100,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 0,
            input: DutchInput(tokenIn1, 1 ether, 1 ether),
            outputs: dutchOutputs
        });
        snapStart("ProtocolFeesGasComparisonTest-InterfaceAndProtocolFeeEthOutput");
        fillContract.execute(SignedOrder(abi.encode(order), signOrder(swapperPrivateKey1, address(permit2), order)));
        snapEnd();
        // fillContract had 1 tokenIn1 preminted to it
        assertEq(tokenIn1.balanceOf(address(fillContract)), 2 ether);
        // swapper had 1 tokenOut1 preminted to it
        assertEq(swapper1.balance, 2 ether);
        // INTERFACE_FEE_RECIPIENT had 1 tokenOut1 preminted to it
        assertEq(INTERFACE_FEE_RECIPIENT.balance, 21 ether / 20);
        // Protocol fee is 5 bps * 1.05
        assertEq(PROTOCOL_FEE_RECIPIENT.balance, 1 ether + 21 ether / 20 * 5 / 10000);
    }
}
