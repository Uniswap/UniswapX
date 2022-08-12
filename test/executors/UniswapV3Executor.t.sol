// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {UniswapV3Executor} from "../../src/sample-executors/UniswapV3Executor.sol";
import {MockERC20} from "../../src/test/MockERC20.sol";
import {Output} from "../../src/interfaces/ReactorStructs.sol";

contract UniswapV3ExecutorTest is Test {
    uint256 takerPrivateKey;
    address taker;
    UniswapV3Executor uniswapV3Executor;

    uint256 constant ONE = 10 ** 18;

    function setUp() public {
        vm.createSelectFork("https://mainnet.infura.io/v3/6e758ef5d39a4fdeba50de7d10d08448", 15327550);
        takerPrivateKey = 0x12341234;
        taker = vm.addr(takerPrivateKey);
        uniswapV3Executor = new UniswapV3Executor();
    }

    function testBase() public {

    }
}