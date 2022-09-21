// SPADIX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {PermitPost, Permit} from "permitpost/PermitPost.sol";
import {Signature, SigType} from "permitpost/interfaces/IPermitPost.sol";
import {OrderInfo, InputToken, ResolvedOrder} from "../../src/base/ReactorStructs.sol";
import {ReactorEvents} from "../../src/base/ReactorEvents.sol";
import {OrderValidator} from "../../src/base/OrderValidator.sol";
import {OrderQuoter} from "../../src/lens/OrderQuoter.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {MockMaker} from "../util/mock/users/MockMaker.sol";
import {MockFillContract} from "../util/mock/MockFillContract.sol";
import {LimitOrder} from "../../src/reactors/limit/LimitOrderStructs.sol";
import {LimitOrderReactor} from "../../src/reactors/limit/LimitOrderReactor.sol";
import {DutchLimitOrder, DutchOutput} from "../../src/reactors/dutch-limit/DutchLimitOrderStructs.sol";
import {DutchLimitOrderReactor} from "../../src/reactors/dutch-limit/DutchLimitOrderReactor.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {PermitSignature} from "../util/PermitSignature.sol";

contract OrderQuoterTest is Test, PermitSignature, ReactorEvents {
    using OrderInfoBuilder for OrderInfo;

    uint256 constant ONE = 10 ** 18;

    OrderQuoter quoter;
    MockERC20 tokenIn;
    MockERC20 tokenOut;
    uint256 makerPrivateKey;
    address maker;
    LimitOrderReactor limitOrderReactor;
    DutchLimitOrderReactor dutchOrderReactor;
    PermitPost permitPost;

    function setUp() public {
        quoter = new OrderQuoter();
        tokenIn = new MockERC20("Input", "IN", 18);
        tokenOut = new MockERC20("Output", "OUT", 18);
        makerPrivateKey = 0x12341234;
        maker = vm.addr(makerPrivateKey);
        tokenIn.mint(address(maker), ONE);
        permitPost = new PermitPost();
        limitOrderReactor = new LimitOrderReactor(address(permitPost));
        dutchOrderReactor = new DutchLimitOrderReactor(address(permitPost));
    }

    function testQuoteLimitOrder() public {
        tokenIn.forceApprove(maker, address(permitPost), ONE);
        LimitOrder memory order = LimitOrder({
            info: OrderInfoBuilder.init(address(limitOrderReactor)).withOfferer(address(maker)),
            input: InputToken(address(tokenIn), ONE),
            outputs: OutputsBuilder.single(address(tokenOut), ONE, address(maker))
        });
        bytes32 orderHash = keccak256(abi.encode(order));
        Signature memory sig = signOrder(vm, makerPrivateKey, address(permitPost), order.info, order.input, orderHash);
        ResolvedOrder memory quote = quoter.quote(abi.encode(order), sig);
        assertEq(quote.input.token, address(tokenIn));
        assertEq(quote.input.amount, ONE);
        assertEq(quote.outputs[0].token, address(tokenOut));
        assertEq(quote.outputs[0].amount, ONE);
    }

    function testQuoteDutchOrder() public {
        tokenIn.forceApprove(maker, address(permitPost), ONE);
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(tokenOut), ONE, ONE * 9 / 10, address(0));
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(dutchOrderReactor)).withOfferer(address(maker)),
            startTime: block.timestamp,
            input: InputToken(address(tokenIn), ONE),
            outputs: dutchOutputs
        });
        bytes32 orderHash = keccak256(abi.encode(order));
        Signature memory sig = signOrder(vm, makerPrivateKey, address(permitPost), order.info, order.input, orderHash);
        ResolvedOrder memory quote = quoter.quote(abi.encode(order), sig);

        assertEq(quote.input.token, address(tokenIn));
        assertEq(quote.input.amount, ONE);
        assertEq(quote.outputs[0].token, address(tokenOut));
        assertEq(quote.outputs[0].amount, ONE);
    }

    function testQuoteDutchOrderAfterDecay() public {
        vm.warp(block.timestamp + 100);
        tokenIn.forceApprove(maker, address(permitPost), ONE);
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(tokenOut), ONE, ONE * 9 / 10, address(0));
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(dutchOrderReactor)).withOfferer(address(maker)),
            startTime: block.timestamp - 100,
            input: InputToken(address(tokenIn), ONE),
            outputs: dutchOutputs
        });
        bytes32 orderHash = keccak256(abi.encode(order));
        Signature memory sig = signOrder(vm, makerPrivateKey, address(permitPost), order.info, order.input, orderHash);
        ResolvedOrder memory quote = quoter.quote(abi.encode(order), sig);

        assertEq(quote.input.token, address(tokenIn));
        assertEq(quote.input.amount, ONE);
        assertEq(quote.outputs[0].token, address(tokenOut));
        assertEq(quote.outputs[0].amount, ONE * 95 / 100);
    }

    function testQuoteLimitOrderDeadlinePassed() public {
        uint256 timestamp = block.timestamp;
        vm.warp(timestamp + 100);
        tokenIn.forceApprove(maker, address(permitPost), ONE);
        LimitOrder memory order = LimitOrder({
            info: OrderInfoBuilder.init(address(limitOrderReactor)).withOfferer(address(maker)).withDeadline(
                block.timestamp - 1
                ),
            input: InputToken(address(tokenIn), ONE),
            outputs: OutputsBuilder.single(address(tokenOut), ONE, address(maker))
        });
        bytes32 orderHash = keccak256(abi.encode(order));
        Signature memory sig = signOrder(vm, makerPrivateKey, address(permitPost), order.info, order.input, orderHash);
        vm.expectRevert(OrderValidator.DeadlinePassed.selector);
        quoter.quote(abi.encode(order), sig);
    }

    function testQuoteLimitOrderInsufficientBalance() public {
        tokenIn.forceApprove(maker, address(permitPost), ONE);
        LimitOrder memory order = LimitOrder({
            info: OrderInfoBuilder.init(address(limitOrderReactor)).withOfferer(address(maker)),
            input: InputToken(address(tokenIn), ONE * 2),
            outputs: OutputsBuilder.single(address(tokenOut), ONE, address(maker))
        });
        bytes32 orderHash = keccak256(abi.encode(order));
        Signature memory sig = signOrder(vm, makerPrivateKey, address(permitPost), order.info, order.input, orderHash);
        vm.expectRevert("TRANSFER_FROM_FAILED");
        quoter.quote(abi.encode(order), sig);
    }

    function testQuoteDutchOrderEndBeforeStart() public {
        tokenIn.forceApprove(maker, address(permitPost), ONE);
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(tokenOut), ONE, ONE * 9 / 10, address(0));
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(dutchOrderReactor)).withOfferer(address(maker)),
            startTime: block.timestamp + 1000,
            input: InputToken(address(tokenIn), ONE),
            outputs: dutchOutputs
        });
        bytes32 orderHash = keccak256(abi.encode(order));
        Signature memory sig = signOrder(vm, makerPrivateKey, address(permitPost), order.info, order.input, orderHash);
        vm.expectRevert(DutchLimitOrderReactor.EndTimeBeforeStart.selector);
        quoter.quote(abi.encode(order), sig);
    }
}
