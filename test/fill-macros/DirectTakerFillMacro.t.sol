// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {Test} from "forge-std/Test.sol";
import {ISignatureTransfer} from "../../src/external/ISignatureTransfer.sol";
import {DeployPermit2} from "../util/DeployPermit2.sol";
import {
    DutchLimitOrderReactor,
    DutchLimitOrder,
    DutchInput,
    DutchOutput
} from "../../src/reactors/DutchLimitOrderReactor.sol";
import {OrderInfo, SignedOrder} from "../../src/base/ReactorStructs.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {DutchLimitOrder, DutchLimitOrderLib} from "../../src/lib/DutchLimitOrderLib.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {PermitSignature} from "../util/PermitSignature.sol";

// This suite of tests test execution with a mock fill contract.
contract DirectTakerFillMacroTest is Test, PermitSignature, GasSnapshot, DeployPermit2 {
    using OrderInfoBuilder for OrderInfo;
    using DutchLimitOrderLib for DutchLimitOrder;

    address constant PROTOCOL_FEE_RECIPIENT = address(2);
    uint256 constant PROTOCOL_FEE_BPS = 5000;

    MockERC20 tokenIn1;
    MockERC20 tokenIn2;
    MockERC20 tokenOut1;
    MockERC20 tokenOut2;
    uint256 makerPrivateKey1;
    address maker1;
    uint256 makerPrivateKey2;
    address maker2;
    address directTaker;
    DutchLimitOrderReactor reactor;
    ISignatureTransfer permit2;

    function setUp() public {
        tokenIn1 = new MockERC20("tokenIn1", "IN1", 18);
        tokenIn2 = new MockERC20("tokenIn2", "IN2", 18);
        tokenOut1 = new MockERC20("tokenOut1", "OUT1", 18);
        tokenOut2 = new MockERC20("tokenOut2", "OUT2", 18);
        makerPrivateKey1 = 0x12341234;
        maker1 = vm.addr(makerPrivateKey1);
        makerPrivateKey2 = 0x12341235;
        maker2 = vm.addr(makerPrivateKey2);
        directTaker = address(888);
        permit2 = deployPermit2();
        reactor = new DutchLimitOrderReactor(address(permit2), PROTOCOL_FEE_BPS, PROTOCOL_FEE_RECIPIENT);
        tokenIn1.forceApprove(maker1, address(permit2), type(uint256).max);
        tokenIn2.forceApprove(maker2, address(permit2), type(uint256).max);
        tokenOut1.forceApprove(directTaker, address(permit2), type(uint256).max);
        tokenOut2.forceApprove(directTaker, address(permit2), type(uint256).max);
        vm.prank(directTaker);
        permit2.approve(address(tokenOut1), address(reactor), type(uint160).max, type(uint48).max);
        vm.prank(directTaker);
        permit2.approve(address(tokenOut2), address(reactor), type(uint160).max, type(uint48).max);
    }

    // Execute a single order made by maker1, input = 1 tokenIn1 and outputs = [2 tokenOut1].
    function testSingleOrder() public {
        uint256 inputAmount = 10 ** 18;
        uint256 outputAmount = 2 * inputAmount;

        tokenIn1.mint(address(maker1), inputAmount);
        tokenOut1.mint(directTaker, outputAmount);

        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker1).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), inputAmount, inputAmount),
            outputs: OutputsBuilder.singleDutch(address(tokenOut1), outputAmount, outputAmount, maker1)
        });

        vm.prank(directTaker);
        snapStart("DirectTakerFillMacroSingleOrder");
        reactor.execute(
            SignedOrder(abi.encode(order), signOrder(makerPrivateKey1, address(permit2), order)), address(1), bytes("")
        );
        snapEnd();
        assertEq(tokenOut1.balanceOf(maker1), outputAmount);
        assertEq(tokenIn1.balanceOf(directTaker), inputAmount);
    }

    // Execute two orders.
    // 1st order by maker1, input = 1 tokenIn1 and outputs = [2 tokenOut1]
    // 2nd order by maker2, input = 3 tokenIn2 and outputs = [1 tokenOut1, 3 tokenOut2]
    function testTwoOrders() public {
        uint256 ONE = 10 ** 18;

        tokenIn1.mint(address(maker1), ONE);
        tokenIn2.mint(address(maker2), ONE * 3);
        tokenOut1.mint(directTaker, ONE * 3);
        tokenOut2.mint(directTaker, ONE * 3);

        DutchLimitOrder memory order1 = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker1).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn1), ONE, ONE),
            outputs: OutputsBuilder.singleDutch(address(tokenOut1), ONE * 2, ONE * 2, maker1)
        });
        DutchOutput[] memory order2Outputs = new DutchOutput[](2);
        order2Outputs[0] = DutchOutput(address(tokenOut1), ONE, ONE, maker2, false);
        order2Outputs[1] = DutchOutput(address(tokenOut2), ONE * 3, ONE * 3, maker2, false);
        DutchLimitOrder memory order2 = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(maker2).withDeadline(block.timestamp + 100),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn2), ONE * 3, ONE * 3),
            outputs: order2Outputs
        });

        SignedOrder[] memory signedOrders = new SignedOrder[](2);
        signedOrders[0] = SignedOrder(abi.encode(order1), signOrder(makerPrivateKey1, address(permit2), order1));
        signedOrders[1] = SignedOrder(abi.encode(order2), signOrder(makerPrivateKey2, address(permit2), order2));
        vm.prank(directTaker);
        snapStart("DirectTakerFillMacroTwoOrders");
        reactor.executeBatch(signedOrders, address(1), bytes(""));
        snapEnd();
    }
}
