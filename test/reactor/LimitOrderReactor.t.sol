// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {PermitPost, Permit} from "permitpost/PermitPost.sol";
import {Signature} from "permitpost/interfaces/IPermitPost.sol";
import {OrderInfo, Output, TokenAmount, ResolvedOrder} from "../../src/lib/ReactorStructs.sol";
import {OrderValidator} from "../../src/lib/OrderValidator.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {MockMaker} from "../util/mock/users/MockMaker.sol";
import {MockFillContract} from "../util/mock/MockFillContract.sol";
import {LimitOrder, LimitOrderExecution} from "../../src/reactor/limit/LimitOrderStructs.sol";
import {LimitOrderReactor} from "../../src/reactor/limit/LimitOrderReactor.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {PermitSignature} from "../util/PermitSignature.sol";

contract LimitOrderReactorTest is Test, PermitSignature {
    using OrderInfoBuilder for OrderInfo;

    uint256 constant ONE = 10 ** 18;

    MockFillContract fillContract;
    MockERC20 tokenIn;
    MockERC20 tokenOut;
    uint256 makerPrivateKey;
    address maker;
    LimitOrderReactor reactor;
    PermitPost permitPost;

    function setUp() public {
        fillContract = new MockFillContract();
        tokenIn = new MockERC20("Input", "IN", 18);
        tokenOut = new MockERC20("Output", "OUT", 18);
        makerPrivateKey = 0x12341234;
        maker = vm.addr(makerPrivateKey);
        tokenIn.mint(address(maker), ONE);
        tokenOut.mint(address(fillContract), ONE);
        permitPost = new PermitPost();
        reactor = new LimitOrderReactor(address(permitPost));
    }

    function testExecute() public {
        tokenIn.forceApprove(maker, address(permitPost), ONE);
        LimitOrder memory order = LimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(address(maker)),
            input: TokenAmount(address(tokenIn), ONE),
            outputs: OutputsBuilder.single(address(tokenOut), ONE, address(maker))
        });
        bytes32 orderHash = keccak256(abi.encode(order));
        LimitOrderExecution memory execution = LimitOrderExecution({
            order: order,
            sig: getPermitSignature(
                vm,
                makerPrivateKey,
                address(permitPost),
                Permit({token: address(tokenIn), spender: address(reactor), maxAmount: ONE, deadline: order.info.deadline}),
                0,
                uint256(orderHash)
                ),
            fillContract: address(fillContract),
            fillData: bytes("")
        });

        uint256 makerInputBalanceStart = tokenIn.balanceOf(address(maker));
        uint256 fillContractInputBalanceStart = tokenIn.balanceOf(address(fillContract));
        uint256 makerOutputBalanceStart = tokenOut.balanceOf(address(maker));
        uint256 fillContractOutputBalanceStart = tokenOut.balanceOf(address(fillContract));

        reactor.execute(execution);

        assertEq(tokenIn.balanceOf(address(maker)), makerInputBalanceStart - ONE);
        assertEq(tokenIn.balanceOf(address(fillContract)), fillContractInputBalanceStart + ONE);
        assertEq(tokenOut.balanceOf(address(maker)), makerOutputBalanceStart + ONE);
        assertEq(tokenOut.balanceOf(address(fillContract)), fillContractOutputBalanceStart - ONE);
    }

    function testExecuteInsufficientPermit() public {
        tokenIn.forceApprove(maker, address(permitPost), ONE);
        LimitOrder memory order = LimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(address(maker)),
            input: TokenAmount(address(tokenIn), ONE),
            outputs: OutputsBuilder.single(address(tokenOut), ONE, address(maker))
        });
        bytes32 orderHash = keccak256(abi.encode(order));
        LimitOrderExecution memory execution = LimitOrderExecution({
            order: order,
            sig: getPermitSignature(
                vm,
                makerPrivateKey,
                address(permitPost),
                Permit({token: address(tokenIn), spender: address(reactor), maxAmount: ONE / 2, deadline: order.info.deadline}),
                0,
                uint256(orderHash)
                ),
            fillContract: address(fillContract),
            fillData: bytes("")
        });

        vm.expectRevert(PermitPost.InvalidSignature.selector);
        reactor.execute(execution);
    }

    function testExecuteIncorrectSpender() public {
        tokenIn.forceApprove(maker, address(permitPost), ONE);
        LimitOrder memory order = LimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(address(maker)),
            input: TokenAmount(address(tokenIn), ONE),
            outputs: OutputsBuilder.single(address(tokenOut), ONE, address(maker))
        });
        bytes32 orderHash = keccak256(abi.encode(order));
        LimitOrderExecution memory execution = LimitOrderExecution({
            order: order,
            sig: getPermitSignature(
                vm,
                makerPrivateKey,
                address(permitPost),
                Permit({token: address(tokenIn), spender: address(this), maxAmount: ONE, deadline: order.info.deadline}),
                0,
                uint256(orderHash)
                ),
            fillContract: address(fillContract),
            fillData: bytes("")
        });

        vm.expectRevert(PermitPost.InvalidSignature.selector);
        reactor.execute(execution);
    }

    function testExecuteIncorrectToken() public {
        tokenIn.forceApprove(maker, address(permitPost), ONE);
        LimitOrder memory order = LimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(address(maker)),
            input: TokenAmount(address(tokenIn), ONE),
            outputs: OutputsBuilder.single(address(tokenOut), ONE, address(maker))
        });
        bytes32 orderHash = keccak256(abi.encode(order));
        LimitOrderExecution memory execution = LimitOrderExecution({
            order: order,
            sig: getPermitSignature(
                vm,
                makerPrivateKey,
                address(permitPost),
                Permit({token: address(tokenOut), spender: address(reactor), maxAmount: ONE, deadline: order.info.deadline}),
                0,
                uint256(orderHash)
                ),
            fillContract: address(fillContract),
            fillData: bytes("")
        });

        vm.expectRevert(PermitPost.InvalidSignature.selector);
        reactor.execute(execution);
    }

    function testResolve() public {
        LimitOrder memory order = LimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(address(maker)),
            input: TokenAmount(address(tokenIn), ONE),
            outputs: OutputsBuilder.single(address(tokenOut), ONE, address(maker))
        });
        ResolvedOrder memory resolved = reactor.resolve(order);
        assertEq(resolved.input.amount, ONE);
        assertEq(resolved.input.token, address(tokenIn));
        assertEq(resolved.outputs.length, 1);
        assertEq(resolved.outputs[0].token, address(tokenOut));
        assertEq(resolved.outputs[0].amount, ONE);
        assertEq(resolved.outputs[0].recipient, address(maker));
    }

    function testValidateInvalidReactor() public {
        LimitOrder memory order = LimitOrder({
            info: OrderInfoBuilder.init(address(0)).withOfferer(address(maker)),
            input: TokenAmount(address(tokenIn), ONE),
            outputs: OutputsBuilder.single(address(tokenOut), ONE, address(maker))
        });
        vm.expectRevert(OrderValidator.InvalidReactor.selector);
        reactor.validate(order);
    }

    function testValidateDeadlinePassed() public {
        uint256 timestamp = block.timestamp;
        vm.warp(timestamp + 100);
        LimitOrder memory order = LimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(address(maker)).withDeadline(block.timestamp - 1),
            input: TokenAmount(address(tokenIn), ONE),
            outputs: OutputsBuilder.single(address(tokenOut), ONE, address(maker))
        });
        vm.expectRevert(OrderValidator.DeadlinePassed.selector);
        reactor.validate(order);
    }
}
