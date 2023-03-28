// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import "forge-std/Test.sol";
import {DeployAggregatorExecutor} from "../../script/DeployAggregatorExecutor.s.sol";
import {AggregatorExecutor} from "../../src/sample-executors/AggregatorExecutor.sol";
import {MockSwapRouter} from "../util/mock/MockSwapRouter.sol";

contract DeployAggregatorExecutorTest is Test {
    DeployAggregatorExecutor deployer;

    address constant OWNER = 0x7C92FdE6A7f83F7DdeFf18BBCF05f374e7CadbCf;
    address constant WETH9 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant SWAPROUTER02 = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
    address constant ONE_INCH_ROUTER = 0x1111111254EEB25477B68fb85Ed929f73A960582;
    address constant REACTOR = 0x81f570f48BE8d3D358404f257b5bDC4A88eefA50;

    function setUp() public {
        vm.createSelectFork(vm.envString("FOUNDRY_RPC_URL"));
        deployer = new DeployAggregatorExecutor();
    }

    function testAggregatorExecutorDeploy() public {
        AggregatorExecutor executor = deployer.run();

        assertEq(AggregatorExecutor(executor).owner(), OWNER);
        assertEq(address(AggregatorExecutor(executor).WETH9()), WETH9);
        assertEq(address(AggregatorExecutor(executor).SWAP_ROUTER_02()), SWAPROUTER02);
        assertEq(AggregatorExecutor(executor).aggregator(), ONE_INCH_ROUTER);
        assertEq(AggregatorExecutor(executor).whitelistedCaller(), OWNER);
        assertEq(AggregatorExecutor(executor).reactor(), REACTOR);
    }
}
