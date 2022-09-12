// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {DirectTakerExecutor} from "../../src/sample-executors/DirectTakerExecutor.sol";
import {DutchLimitOrderReactor, DutchLimitOrder} from "../../src/reactor/dutch-limit/DutchLimitOrderReactor.sol";
import {DutchLimitOrderExecution} from "../../src/reactor/dutch-limit/DutchLimitOrderStructs.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";
import {Output, TokenAmount, OrderInfo, ResolvedOrder} from "../../src/lib/ReactorStructs.sol";
import {PermitPost, Permit} from "permitpost/PermitPost.sol";
import {SigType} from "permitpost/interfaces/IPermitPost.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {OutputsBuilder} from "../util/OutputsBuilder.sol";
import {PermitSignature} from "../util/PermitSignature.sol";

contract DirectTakerExecutorTest is Test, PermitSignature {
    using OrderInfoBuilder for OrderInfo;

    uint256 takerPrivateKey;
    uint256 makerPrivateKey;
    MockERC20 tokenIn;
    MockERC20 tokenOut;
    address taker;
    address maker;
    DirectTakerExecutor directTakerExecutor;
    DutchLimitOrderReactor dloReactor;
    PermitPost permitPost;

    uint256 constant ONE = 10 ** 18;

    function setUp() public {
        vm.warp(1660671678);

        // Mock input/output tokens
        tokenIn = new MockERC20("Input", "IN", 18);
        tokenOut = new MockERC20("Output", "OUT", 18);

        // Mock taker
        takerPrivateKey = 0x12341234;
        taker = vm.addr(takerPrivateKey);
        makerPrivateKey = 0x12341235;
        maker = vm.addr(makerPrivateKey);

        // Instantiate relevant contracts
        directTakerExecutor = new DirectTakerExecutor();
        permitPost = new PermitPost();
        dloReactor = new DutchLimitOrderReactor(address(permitPost));

        // Do appropriate max approvals
        tokenOut.forceApprove(taker, address(directTakerExecutor), type(uint256).max);
        tokenIn.forceApprove(maker, address(permitPost), type(uint256).max);
    }

    function testReactorCallback() public {
        uint256 inputAmount = ONE;
        uint256 outputAmount = ONE;

        Output[] memory outputs = new Output[](1);
        outputs[0].token = address(tokenOut);
        outputs[0].amount = outputAmount;
        ResolvedOrder[] memory resolvedOrders = new ResolvedOrder[](1);
        ResolvedOrder memory resolvedOrder = ResolvedOrder(
            OrderInfoBuilder.init(address(dloReactor)), TokenAmount(address(tokenIn), inputAmount), outputs
        );
        resolvedOrders[0] = resolvedOrder;
        bytes memory fillData = abi.encode(taker, dloReactor);
        tokenIn.mint(address(directTakerExecutor), inputAmount);
        tokenOut.mint(taker, outputAmount);
        directTakerExecutor.reactorCallback(resolvedOrders, fillData);
        assertEq(tokenIn.balanceOf(taker), inputAmount);
        assertEq(tokenOut.balanceOf(address(directTakerExecutor)), outputAmount);
    }

    function testReactorCallback2Outputs() public {
        uint256 inputAmount = ONE;

        Output[] memory outputs = new Output[](2);
        outputs[0].token = address(tokenOut);
        outputs[0].amount = ONE;
        outputs[1].token = address(tokenOut);
        outputs[1].amount = ONE * 2;
        ResolvedOrder[] memory resolvedOrders = new ResolvedOrder[](1);
        ResolvedOrder memory resolvedOrder = ResolvedOrder(
            OrderInfoBuilder.init(address(dloReactor)), TokenAmount(address(tokenIn), inputAmount), outputs
        );
        resolvedOrders[0] = resolvedOrder;
        bytes memory fillData = abi.encode(taker, dloReactor);
        tokenOut.mint(taker, ONE * 3);
        tokenIn.mint(address(directTakerExecutor), inputAmount);
        directTakerExecutor.reactorCallback(resolvedOrders, fillData);
        assertEq(tokenIn.balanceOf(taker), inputAmount);
        assertEq(tokenOut.balanceOf(address(directTakerExecutor)), ONE * 3);
    }

    function testExecute() public {
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(dloReactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: TokenAmount(address(tokenIn), ONE),
            // The total outputs will resolve to 1.5
            outputs: OutputsBuilder.singleDutch(address(tokenOut), ONE * 2, ONE, address(maker))
        });
        bytes32 orderHash = keccak256(abi.encode(order));

        tokenIn.mint(maker, ONE);
        tokenOut.mint(taker, ONE * 2);

        dloReactor.execute(
            order,
            signOrder(vm, makerPrivateKey, address(permitPost), order.info, order.input, orderHash),
            address(directTakerExecutor),
            abi.encode(taker, dloReactor)
        );
        assertEq(tokenIn.balanceOf(maker), 0);
        assertEq(tokenIn.balanceOf(taker), ONE);
        assertEq(tokenOut.balanceOf(maker), 1500000000000000000);
        assertEq(tokenOut.balanceOf(taker), 500000000000000000);
    }
}
