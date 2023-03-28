// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console2.sol";
import "forge-std/Script.sol";
import {AggregatorExecutor} from "../src/sample-executors/AggregatorExecutor.sol";

contract DeployAggregatorExecutor is Script {
    function setUp() public {}

    function run() public returns (AggregatorExecutor executor) {
        address reactor = vm.envAddress("REACTOR_ADDRESS");
        address whitelistedCaller = vm.envAddress("AGGREGATOR_EXECUTOR_WHITELISTED_CALLER_ADDRESS");
        address owner = vm.envAddress("AGGREGATOR_EXECUTOR_OWNER_ADDRESS");
        address aggregator = vm.envAddress("ONE_INCH_ROUTER_ADDRESS");
        address swapRouter02 = vm.envAddress("SWAPROUTER02_ADDRESS");

        vm.startBroadcast();
        executor = new AggregatorExecutor{salt: 0x00}(whitelistedCaller, reactor, owner, aggregator, swapRouter02);
        vm.stopBroadcast();

        console2.log("AggregatorExecutor", address(executor));
        console2.log("owner", executor.owner());
    }
}
