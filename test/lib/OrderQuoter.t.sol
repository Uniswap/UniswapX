// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {OrderInfo, InputToken, ResolvedOrder} from "../../src/base/ReactorStructs.sol";
import {ReactorEvents} from "../../src/base/ReactorEvents.sol";
import {ResolvedOrderLib} from "../../src/lib/ResolvedOrderLib.sol";
import {DutchDecayLib} from "../../src/lib/DutchDecayLib.sol";
import {OrderQuoter} from "../../src/lens/OrderQuoter.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {DeployPermit2} from "../util/DeployPermit2.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {MockSwapper} from "../util/mock/users/MockSwapper.sol";
import {MockFillContract} from "../util/mock/MockFillContract.sol";
import {MockOrder} from "../util/mock/MockOrderStruct.sol";
import {LimitOrderReactor, LimitOrder} from "../../src/reactors/LimitOrderReactor.sol";
import {
    DutchLimitOrderReactor,
    DutchLimitOrder,
    DutchOutput,
    DutchInput
} from "../../src/reactors/DutchLimitOrderReactor.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {PermitSignature} from "../util/PermitSignature.sol";

contract OrderQuoterTest is Test, PermitSignature, ReactorEvents, DeployPermit2 {
    using OrderInfoBuilder for OrderInfo;

    uint256 constant ONE = 10 ** 18;
    address constant PROTOCOL_FEE_RECIPIENT = address(1);
    uint256 constant PROTOCOL_FEE_BPS = 5000;

    OrderQuoter quoter;
    MockERC20 tokenIn;
    MockERC20 tokenOut;
    uint256 swapperPrivateKey;
    address swapper;
    LimitOrderReactor limitOrderReactor;
    DutchLimitOrderReactor dutchOrderReactor;
    ISignatureTransfer permit2;

    function setUp() public {
        quoter = new OrderQuoter();
        tokenIn = new MockERC20("Input", "IN", 18);
        tokenOut = new MockERC20("Output", "OUT", 18);
        swapperPrivateKey = 0x12341234;
        swapper = vm.addr(swapperPrivateKey);
        tokenIn.mint(address(swapper), ONE);
        permit2 = ISignatureTransfer(deployPermit2());
        limitOrderReactor = new LimitOrderReactor(address(permit2), PROTOCOL_FEE_BPS, PROTOCOL_FEE_RECIPIENT);
        dutchOrderReactor = new DutchLimitOrderReactor(address(permit2), PROTOCOL_FEE_BPS, PROTOCOL_FEE_RECIPIENT);
    }

    function testQuoteLimitOrder() public {
        tokenIn.forceApprove(swapper, address(permit2), ONE);
        LimitOrder memory order = LimitOrder({
            info: OrderInfoBuilder.init(address(limitOrderReactor)).withSwapper(address(swapper)),
            input: InputToken(address(tokenIn), ONE, ONE),
            outputs: OutputsBuilder.single(address(tokenOut), ONE, address(swapper))
        });
        bytes memory sig = signOrder(swapperPrivateKey, address(permit2), order);
        ResolvedOrder memory quote = quoter.quote(abi.encode(order), sig);
        assertEq(quote.input.token, address(tokenIn));
        assertEq(quote.input.amount, ONE);
        assertEq(quote.outputs[0].token, address(tokenOut));
        assertEq(quote.outputs[0].amount, ONE);
    }

    function testQuoteDutchOrder() public {
        tokenIn.forceApprove(swapper, address(permit2), ONE);
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(tokenOut), ONE, ONE * 9 / 10, address(0), false);
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(dutchOrderReactor)).withSwapper(address(swapper)),
            startTime: block.timestamp,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn), ONE, ONE),
            outputs: dutchOutputs
        });
        bytes memory sig = signOrder(swapperPrivateKey, address(permit2), order);
        ResolvedOrder memory quote = quoter.quote(abi.encode(order), sig);

        assertEq(quote.input.token, address(tokenIn));
        assertEq(quote.input.amount, ONE);
        assertEq(quote.outputs[0].token, address(tokenOut));
        assertEq(quote.outputs[0].amount, ONE);
    }

    function testQuoteDutchOrderAfterOutputDecay() public {
        vm.warp(block.timestamp + 100);
        tokenIn.forceApprove(swapper, address(permit2), ONE);
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(tokenOut), ONE, ONE * 9 / 10, address(0), false);
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(dutchOrderReactor)).withSwapper(address(swapper)),
            startTime: block.timestamp - 100,
            endTime: 201,
            input: DutchInput(address(tokenIn), ONE, ONE),
            outputs: dutchOutputs
        });
        bytes memory sig = signOrder(swapperPrivateKey, address(permit2), order);
        ResolvedOrder memory quote = quoter.quote(abi.encode(order), sig);

        assertEq(quote.input.token, address(tokenIn));
        assertEq(quote.input.amount, ONE);
        assertEq(quote.outputs[0].token, address(tokenOut));
        assertEq(quote.outputs[0].amount, ONE * 95 / 100);
    }

    function testQuoteDutchOrderAfterInputDecay() public {
        vm.warp(block.timestamp + 100);
        tokenIn.forceApprove(swapper, address(permit2), ONE);
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(tokenOut), ONE, ONE, address(0), false);
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(dutchOrderReactor)).withSwapper(address(swapper)),
            startTime: block.timestamp - 100,
            endTime: 201,
            input: DutchInput(address(tokenIn), ONE * 9 / 10, ONE),
            outputs: dutchOutputs
        });
        bytes memory sig = signOrder(swapperPrivateKey, address(permit2), order);
        ResolvedOrder memory quote = quoter.quote(abi.encode(order), sig);

        assertEq(quote.input.token, address(tokenIn));
        assertEq(quote.input.amount, ONE * 95 / 100);
        assertEq(quote.outputs[0].token, address(tokenOut));
        assertEq(quote.outputs[0].amount, ONE);
    }

    function testQuoteLimitOrderDeadlinePassed() public {
        uint256 timestamp = block.timestamp;
        vm.warp(timestamp + 100);
        tokenIn.forceApprove(swapper, address(permit2), ONE);
        LimitOrder memory order = LimitOrder({
            info: OrderInfoBuilder.init(address(limitOrderReactor)).withSwapper(address(swapper)).withDeadline(
                block.timestamp - 1
                ),
            input: InputToken(address(tokenIn), ONE, ONE),
            outputs: OutputsBuilder.single(address(tokenOut), ONE, address(swapper))
        });
        bytes memory sig = signOrder(swapperPrivateKey, address(permit2), order);
        vm.expectRevert(ResolvedOrderLib.DeadlinePassed.selector);
        quoter.quote(abi.encode(order), sig);
    }

    function testQuoteLimitOrderInsufficientBalance() public {
        tokenIn.forceApprove(swapper, address(permit2), ONE);
        LimitOrder memory order = LimitOrder({
            info: OrderInfoBuilder.init(address(limitOrderReactor)).withSwapper(address(swapper)),
            input: InputToken(address(tokenIn), ONE * 2, ONE * 2),
            outputs: OutputsBuilder.single(address(tokenOut), ONE, address(swapper))
        });
        bytes memory sig = signOrder(swapperPrivateKey, address(permit2), order);
        vm.expectRevert("TRANSFER_FROM_FAILED");
        quoter.quote(abi.encode(order), sig);
    }

    function testQuoteDutchOrderEndBeforeStart() public {
        tokenIn.forceApprove(swapper, address(permit2), ONE);
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(tokenOut), ONE, ONE * 9 / 10, address(0), false);
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(dutchOrderReactor)).withSwapper(address(swapper)),
            startTime: block.timestamp + 1000,
            endTime: block.timestamp + 100,
            input: DutchInput(address(tokenIn), ONE, ONE),
            outputs: dutchOutputs
        });
        bytes memory sig = signOrder(swapperPrivateKey, address(permit2), order);
        vm.expectRevert(DutchDecayLib.EndTimeBeforeStartTime.selector);
        quoter.quote(abi.encode(order), sig);
    }

    function testGetReactorLimitOrder() public {
        LimitOrder memory order = LimitOrder({
            info: OrderInfoBuilder.init(address(0x1234)),
            input: InputToken(address(tokenIn), ONE, ONE),
            outputs: OutputsBuilder.single(address(tokenOut), ONE, address(swapper))
        });
        address reactor = quoter.getReactor(abi.encode(order));
        assertEq(reactor, address(0x1234));
    }

    function testGetReactorDutchOrder() public {
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(tokenOut), ONE, ONE * 9 / 10, address(0), false);
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(0x2345)),
            startTime: block.timestamp + 1000,
            endTime: block.timestamp + 1100,
            input: DutchInput(address(tokenIn), ONE, ONE),
            outputs: dutchOutputs
        });
        address reactor = quoter.getReactor(abi.encode(order));
        assertEq(reactor, address(0x2345));
    }

    function testGetReactorMockOrder() public {
        MockOrder memory order = MockOrder({
            info: OrderInfoBuilder.init(address(0x3456)),
            mockField1: 0,
            mockField2: 0,
            mockField3: 0,
            mockField4: 0,
            mockField5: 0,
            mockField6: 0,
            mockField7: 0,
            mockField8: 0,
            mockField9: 0
        });
        address reactor = quoter.getReactor(abi.encode(order));
        assertEq(reactor, address(0x3456));
    }
}
