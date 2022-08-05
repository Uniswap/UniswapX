// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {DirectTakerExecutor} from "../../src/sample-executors/DirectTakerExecutor.sol";
import {MockERC20} from "../../src/test/MockERC20.sol";
import {Output} from "../../src/interfaces/ReactorStructs.sol";

contract DirectTakerExecutorTest is Test {
    uint256 takerPrivateKey;
    MockERC20 tokenIn;
    MockERC20 tokenOut;
    address taker;
    DirectTakerExecutor directTakerExecutor;

    uint256 constant ONE = 10 ** 18;

    function setUp() public {
        tokenIn = new MockERC20("Input", "IN", 18);
        tokenOut = new MockERC20("Output", "OUT", 18);
        takerPrivateKey = 0x12341234;
        taker = vm.addr(takerPrivateKey);
        directTakerExecutor = new DirectTakerExecutor();
        tokenIn.mint(address(directTakerExecutor), ONE);
        tokenOut.mint(taker, ONE);
        tokenOut.forceApprove(taker, address(directTakerExecutor), ONE);
    }

    function testReactorCallback() public {
        Output[] memory outputs = new Output[](1);
        outputs[0].token = address(tokenOut);
        outputs[0].amount = ONE;
        bytes memory fillData = abi.encode(taker, tokenIn, ONE);
        directTakerExecutor.reactorCallback(outputs, fillData);
        assertEq(tokenIn.balanceOf(taker), ONE);
        assertEq(tokenOut.balanceOf(address(directTakerExecutor)), ONE);
    }
}