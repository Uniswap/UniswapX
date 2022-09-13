// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {PermitPost, Permit} from "permitpost/PermitPost.sol";
import {Signature, SigType} from "permitpost/interfaces/IPermitPost.sol";
import {OrderInfo, Output, TokenAmount, ResolvedOrder, SignedOrder} from "../../src/lib/ReactorStructs.sol";
import {ReactorEvents} from "../../src/lib/ReactorEvents.sol";
import {OrderValidator} from "../../src/lib/OrderValidator.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {MockMaker} from "../util/mock/users/MockMaker.sol";
import {MockFillContract} from "../util/mock/MockFillContract.sol";
import {LimitOrder} from "../../src/reactor/limit/LimitOrderStructs.sol";
import {LimitOrderReactor} from "../../src/reactor/limit/LimitOrderReactor.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {PermitSignature} from "../util/PermitSignature.sol";

contract LimitOrderReactorTest is Test, PermitSignature, ReactorEvents {
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
        Signature memory sig = signOrder(vm, makerPrivateKey, address(permitPost), order.info, order.input, orderHash);

        uint256 makerInputBalanceStart = tokenIn.balanceOf(address(maker));
        uint256 fillContractInputBalanceStart = tokenIn.balanceOf(address(fillContract));
        uint256 makerOutputBalanceStart = tokenOut.balanceOf(address(maker));
        uint256 fillContractOutputBalanceStart = tokenOut.balanceOf(address(fillContract));

        vm.expectEmit(false, false, false, true, address(reactor));
        emit Fill(orderHash, address(this));

        reactor.execute(SignedOrder(abi.encode(order), sig), address(fillContract), bytes(""));

        assertEq(tokenIn.balanceOf(address(maker)), makerInputBalanceStart - ONE);
        assertEq(tokenIn.balanceOf(address(fillContract)), fillContractInputBalanceStart + ONE);
        assertEq(tokenOut.balanceOf(address(maker)), makerOutputBalanceStart + ONE);
        assertEq(tokenOut.balanceOf(address(fillContract)), fillContractOutputBalanceStart - ONE);
    }

    function testExecuteNonceReuse() public {
        tokenIn.forceApprove(maker, address(permitPost), ONE);
        uint256 nonce = 1234;
        LimitOrder memory order = LimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(address(maker)).withNonce(nonce),
            input: TokenAmount(address(tokenIn), ONE),
            outputs: OutputsBuilder.single(address(tokenOut), ONE, address(maker))
        });
        bytes32 orderHash = keccak256(abi.encode(order));
        Signature memory sig = signOrder(vm, makerPrivateKey, address(permitPost), order.info, order.input, orderHash);
        reactor.execute(SignedOrder(abi.encode(order), sig), address(fillContract), bytes(""));

        tokenIn.mint(address(maker), ONE * 2);
        tokenOut.mint(address(fillContract), ONE * 2);
        tokenIn.forceApprove(maker, address(permitPost), ONE * 2);
        LimitOrder memory order2 = LimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(address(maker)).withNonce(nonce),
            input: TokenAmount(address(tokenIn), ONE * 2),
            outputs: OutputsBuilder.single(address(tokenOut), ONE * 2, address(maker))
        });
        bytes32 orderHash2 = keccak256(abi.encode(order));
        Signature memory sig2 =
            signOrder(vm, makerPrivateKey, address(permitPost), order2.info, order2.input, orderHash2);
        vm.expectRevert(PermitPost.NonceUsed.selector);
        reactor.execute(SignedOrder(abi.encode(order2), sig2), address(fillContract), bytes(""));
    }

    function testExecuteInsufficientPermit() public {
        tokenIn.forceApprove(maker, address(permitPost), ONE);
        LimitOrder memory order = LimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(address(maker)),
            input: TokenAmount(address(tokenIn), ONE),
            outputs: OutputsBuilder.single(address(tokenOut), ONE, address(maker))
        });
        bytes32 orderHash = keccak256(abi.encode(order));
        Signature memory sig = signOrder(
            vm, makerPrivateKey, address(permitPost), order.info, TokenAmount(address(tokenIn), ONE / 2), orderHash
        );

        vm.expectRevert(PermitPost.InvalidSignature.selector);
        reactor.execute(SignedOrder(abi.encode(order), sig), address(fillContract), bytes(""));
    }

    function testExecuteIncorrectSpender() public {
        tokenIn.forceApprove(maker, address(permitPost), ONE);
        LimitOrder memory order = LimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(address(maker)),
            input: TokenAmount(address(tokenIn), ONE),
            outputs: OutputsBuilder.single(address(tokenOut), ONE, address(maker))
        });
        bytes32 orderHash = keccak256(abi.encode(order));
        Signature memory sig = signOrder(
            vm,
            makerPrivateKey,
            address(permitPost),
            OrderInfoBuilder.init(address(this)).withOfferer(address(maker)),
            order.input,
            orderHash
        );

        vm.expectRevert(PermitPost.InvalidSignature.selector);
        reactor.execute(SignedOrder(abi.encode(order), sig), address(fillContract), bytes(""));
    }

    function testExecuteIncorrectToken() public {
        tokenIn.forceApprove(maker, address(permitPost), ONE);
        LimitOrder memory order = LimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(address(maker)),
            input: TokenAmount(address(tokenIn), ONE),
            outputs: OutputsBuilder.single(address(tokenOut), ONE, address(maker))
        });
        bytes32 orderHash = keccak256(abi.encode(order));

        Signature memory sig = signOrder(
            vm, makerPrivateKey, address(permitPost), order.info, TokenAmount(address(tokenOut), ONE), orderHash
        );
        vm.expectRevert(PermitPost.InvalidSignature.selector);
        reactor.execute(SignedOrder(abi.encode(order), sig), address(fillContract), bytes(""));
    }

    function testResolve() public {
        LimitOrder memory order = LimitOrder({
            info: OrderInfoBuilder.init(address(reactor)).withOfferer(address(maker)),
            input: TokenAmount(address(tokenIn), ONE),
            outputs: OutputsBuilder.single(address(tokenOut), ONE, address(maker))
        });
        ResolvedOrder memory resolved = reactor.resolve(abi.encode(order));
        assertEq(resolved.input.amount, ONE);
        assertEq(resolved.input.token, address(tokenIn));
        assertEq(resolved.outputs.length, 1);
        assertEq(resolved.outputs[0].token, address(tokenOut));
        assertEq(resolved.outputs[0].amount, ONE);
        assertEq(resolved.outputs[0].recipient, address(maker));
    }
}
