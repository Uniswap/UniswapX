// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {DirectTakerExecutor} from "../../src/sample-executors/DirectTakerExecutor.sol";
import {DutchLimitOrderReactor, DutchLimitOrder, DutchLimitOrderExecution} from "../../src/reactor/dutch-limit/DutchLimitOrderReactor.sol";
import {MockERC20} from "../../src/test/MockERC20.sol";
import {Output, TokenAmount, OrderInfo} from "../../src/interfaces/ReactorStructs.sol";
import {PermitPost, Permit} from "permitpost/PermitPost.sol";
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
        Output[] memory outputs = new Output[](1);
        outputs[0].token = address(tokenOut);
        outputs[0].amount = ONE;
        bytes memory fillData = abi.encode(taker, tokenIn, ONE, dloReactor);
        tokenIn.mint(address(directTakerExecutor), ONE);
        tokenOut.mint(taker, ONE);
        directTakerExecutor.reactorCallback(outputs, fillData);
        assertEq(tokenIn.balanceOf(taker), ONE);
        assertEq(tokenOut.balanceOf(address(directTakerExecutor)), ONE);
    }

    function testReactorCallback2Outputs() public {
        Output[] memory outputs = new Output[](2);
        outputs[0].token = address(tokenOut);
        outputs[0].amount = ONE;
        outputs[1].token = address(tokenOut);
        outputs[1].amount = ONE * 2;
        bytes memory fillData = abi.encode(taker, tokenIn, ONE, dloReactor);
        tokenOut.mint(taker, ONE * 3);
        tokenIn.mint(address(directTakerExecutor), ONE);
        directTakerExecutor.reactorCallback(outputs, fillData);
        assertEq(tokenIn.balanceOf(taker), ONE);
        assertEq(tokenOut.balanceOf(address(directTakerExecutor)), ONE * 3);
    }

    function testExecute() public {
        DutchLimitOrder memory order = DutchLimitOrder({
            info: OrderInfoBuilder.init(address(dloReactor)).withOfferer(maker).withDeadline(block.timestamp + 100),
            startTime: block.timestamp - 100,
            endTime: block.timestamp + 100,
            input: TokenAmount(address(tokenIn), ONE),
            outputs: OutputsBuilder.singleDutch(address(tokenOut), ONE * 2, ONE, address(maker))
        });
        bytes32 orderHash = keccak256(abi.encode(order));
        DutchLimitOrderExecution memory execution = DutchLimitOrderExecution({
            order: order,
            sig: getPermitSignature(
                vm,
                makerPrivateKey,
                address(permitPost),
                Permit({
                    token: address(tokenIn),
                    spender: address(dloReactor),
                    maxAmount: ONE,
                    deadline: order.info.deadline
                }),
                0,
                uint256(orderHash)
            ),
            fillContract: address(directTakerExecutor),
            fillData: abi.encode(taker, tokenIn, ONE, dloReactor)
        });

        tokenIn.mint(maker, ONE);
        tokenOut.mint(taker, ONE * 2);
        dloReactor.execute(execution);
    }
}