// SPADIX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {Test} from "forge-std/Test.sol";
import {Permit2} from "permit2/Permit2.sol";
import {OrderInfo, InputToken, ResolvedOrder} from "../../src/base/ReactorStructs.sol";
import {ReactorEvents} from "../../src/base/ReactorEvents.sol";
import {OrderInfoLib} from "../../src/lib/OrderInfoLib.sol";
import {OrderQuoter} from "../../src/lens/OrderQuoter.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {MockMaker} from "../util/mock/users/MockMaker.sol";
import {MockFillContract} from "../util/mock/MockFillContract.sol";
import {LimitOrderReactor, LimitOrder} from "../../src/reactors/LimitOrderReactor.sol";
import {DutchLimitOrderReactor, DutchLimitOrder, DutchOutput} from "../../src/reactors/DutchLimitOrderReactor.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {TestOrderHashing} from "../util/TestOrderHashing.sol";

contract OrderQuoterTest is Test, PermitSignature, ReactorEvents, TestOrderHashing {
    using OrderInfoBuilder for OrderInfo;

    uint256 constant ONE = 10 ** 18;

    OrderQuoter quoter;
    MockERC20 tokenIn;
    MockERC20 tokenOut;
    uint256 makerPrivateKey;
    address maker;
    LimitOrderReactor limitOrderReactor;
    DutchLimitOrderReactor dutchOrderReactor;
    Permit2 permit2;

    function setUp() public {
        quoter = new OrderQuoter();
        tokenIn = new MockERC20("Input", "IN", 18);
        tokenOut = new MockERC20("Output", "OUT", 18);
        makerPrivateKey = 0x12341234;
        maker = vm.addr(makerPrivateKey);
        tokenIn.mint(address(maker), ONE);
        permit2 = new Permit2();
        limitOrderReactor = new LimitOrderReactor(address(permit2));
        dutchOrderReactor = new DutchLimitOrderReactor(address(permit2));
    }

    function testQuoteLimitOrder() public {
        tokenIn.forceApprove(maker, address(permit2), ONE);
        LimitOrder memory order = LimitOrder({
            info: OrderInfoBuilder.init(address(limitOrderReactor)).withOfferer(address(maker)),
            input: InputToken(address(tokenIn), ONE),
            outputs: OutputsBuilder.single(address(tokenOut), ONE, address(maker))
        });
        bytes memory sig =
            signOrder(makerPrivateKey, address(permit2), order.info, order.input, LIMIT_ORDER_TYPE_HASH, hash(order));
        ResolvedOrder memory quote = quoter.quote(abi.encode(order), sig);
        assertEq(quote.input.token, address(tokenIn));
        assertEq(quote.input.amount, ONE);
        assertEq(quote.outputs[0].token, address(tokenOut));
        assertEq(quote.outputs[0].amount, ONE);
    }

    function testQuoteDutchOrder() public {
        tokenIn.forceApprove(maker, address(permit2), ONE);
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(tokenOut), ONE, ONE * 9 / 10, address(0));
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(dutchOrderReactor)).withOfferer(address(maker)),
            startTime: block.timestamp,
            input: InputToken(address(tokenIn), ONE),
            outputs: dutchOutputs
        });
        bytes memory sig =
            signOrder(makerPrivateKey, address(permit2), order.info, order.input, DUTCH_ORDER_TYPE_HASH, hash(order));
        ResolvedOrder memory quote = quoter.quote(abi.encode(order), sig);

        assertEq(quote.input.token, address(tokenIn));
        assertEq(quote.input.amount, ONE);
        assertEq(quote.outputs[0].token, address(tokenOut));
        assertEq(quote.outputs[0].amount, ONE);
    }

    function testQuoteDutchOrderAfterDecay() public {
        vm.warp(block.timestamp + 100);
        tokenIn.forceApprove(maker, address(permit2), ONE);
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(tokenOut), ONE, ONE * 9 / 10, address(0));
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(dutchOrderReactor)).withOfferer(address(maker)),
            startTime: block.timestamp - 100,
            input: InputToken(address(tokenIn), ONE),
            outputs: dutchOutputs
        });
        bytes memory sig =
            signOrder(makerPrivateKey, address(permit2), order.info, order.input, DUTCH_ORDER_TYPE_HASH, hash(order));
        ResolvedOrder memory quote = quoter.quote(abi.encode(order), sig);

        assertEq(quote.input.token, address(tokenIn));
        assertEq(quote.input.amount, ONE);
        assertEq(quote.outputs[0].token, address(tokenOut));
        assertEq(quote.outputs[0].amount, ONE * 95 / 100);
    }

    function testQuoteLimitOrderDeadlinePassed() public {
        uint256 timestamp = block.timestamp;
        vm.warp(timestamp + 100);
        tokenIn.forceApprove(maker, address(permit2), ONE);
        LimitOrder memory order = LimitOrder({
            info: OrderInfoBuilder.init(address(limitOrderReactor)).withOfferer(address(maker)).withDeadline(
                block.timestamp - 1
                ),
            input: InputToken(address(tokenIn), ONE),
            outputs: OutputsBuilder.single(address(tokenOut), ONE, address(maker))
        });
        bytes memory sig =
            signOrder(makerPrivateKey, address(permit2), order.info, order.input, LIMIT_ORDER_TYPE_HASH, hash(order));
        vm.expectRevert(OrderInfoLib.DeadlinePassed.selector);
        quoter.quote(abi.encode(order), sig);
    }

    function testQuoteLimitOrderInsufficientBalance() public {
        tokenIn.forceApprove(maker, address(permit2), ONE);
        LimitOrder memory order = LimitOrder({
            info: OrderInfoBuilder.init(address(limitOrderReactor)).withOfferer(address(maker)),
            input: InputToken(address(tokenIn), ONE * 2),
            outputs: OutputsBuilder.single(address(tokenOut), ONE, address(maker))
        });
        bytes memory sig =
            signOrder(makerPrivateKey, address(permit2), order.info, order.input, LIMIT_ORDER_TYPE_HASH, hash(order));
        vm.expectRevert("TRANSFER_FROM_FAILED");
        quoter.quote(abi.encode(order), sig);
    }

    function testQuoteDutchOrderEndBeforeStart() public {
        tokenIn.forceApprove(maker, address(permit2), ONE);
        DutchOutput[] memory dutchOutputs = new DutchOutput[](1);
        dutchOutputs[0] = DutchOutput(address(tokenOut), ONE, ONE * 9 / 10, address(0));
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(dutchOrderReactor)).withOfferer(address(maker)),
            startTime: block.timestamp + 1000,
            input: InputToken(address(tokenIn), ONE),
            outputs: dutchOutputs
        });
        bytes memory sig =
            signOrder(makerPrivateKey, address(permit2), order.info, order.input, DUTCH_ORDER_TYPE_HASH, hash(order));
        vm.expectRevert(DutchLimitOrderReactor.EndTimeBeforeStart.selector);
        quoter.quote(abi.encode(order), sig);
    }
}
