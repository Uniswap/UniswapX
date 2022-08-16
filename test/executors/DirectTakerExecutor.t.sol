// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {DirectTakerExecutor} from "../../src/sample-executors/DirectTakerExecutor.sol";
import {DutchLimitOrderReactor} from "../../src/reactor/dutch-limit/DutchLimitOrderReactor.sol";
import {MockERC20} from "../../src/test/MockERC20.sol";
import {Output} from "../../src/interfaces/ReactorStructs.sol";
import {PermitPost, Permit} from "permitpost/PermitPost.sol";

contract DirectTakerExecutorTest is Test {
    uint256 takerPrivateKey;
    MockERC20 tokenIn;
    MockERC20 tokenOut;
    address taker;
    DirectTakerExecutor directTakerExecutor;
    DutchLimitOrderReactor dloReactor;
    PermitPost permitPost;

    uint256 constant ONE = 10 ** 18;

    function setUp() public {
        // Mock input/output tokens
        tokenIn = new MockERC20("Input", "IN", 18);
        tokenOut = new MockERC20("Output", "OUT", 18);

        // Mock taker
        takerPrivateKey = 0x12341234;
        taker = vm.addr(takerPrivateKey);

        // Instantiate relevant contracts
        directTakerExecutor = new DirectTakerExecutor();
        permitPost = new PermitPost();
        dloReactor = new DutchLimitOrderReactor(address(permitPost));

        // Give 1 tokenIn to executor, 1 tokenOut to taker
        tokenIn.mint(address(directTakerExecutor), ONE);
        tokenOut.mint(taker, ONE);
        tokenOut.forceApprove(taker, address(directTakerExecutor), ONE);
    }

    function testReactorCallback() public {
        Output[] memory outputs = new Output[](1);
        outputs[0].token = address(tokenOut);
        outputs[0].amount = ONE;
        bytes memory fillData = abi.encode(taker, tokenIn, ONE, dloReactor);
        directTakerExecutor.reactorCallback(outputs, fillData);
        assertEq(tokenIn.balanceOf(taker), ONE);
        assertEq(tokenOut.balanceOf(address(directTakerExecutor)), ONE);
    }

    function testReactorCallback2Outputs() public {
        Output[] memory outputs = new Output[](2);
        tokenOut.mint(taker, ONE * 2);
        tokenOut.forceApprove(taker, address(directTakerExecutor), ONE * 3);
        outputs[0].token = address(tokenOut);
        outputs[0].amount = ONE;
        outputs[1].token = address(tokenOut);
        outputs[1].amount = ONE * 2;
        bytes memory fillData = abi.encode(taker, tokenIn, ONE, dloReactor);
        directTakerExecutor.reactorCallback(outputs, fillData);
        assertEq(tokenIn.balanceOf(taker), ONE);
        assertEq(tokenOut.balanceOf(address(directTakerExecutor)), ONE * 3);
    }
}