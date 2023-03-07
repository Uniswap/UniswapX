// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console2.sol";
import "forge-std/Script.sol";
import {SwapRouter02Executor} from "../src/sample-executors/SwapRouter02Executor.sol";

contract DeploySwapRouter02Executor is Script {
    function setUp() public {}

    function run() public returns (SwapRouter02Executor executor) {
        uint256 privateKey = vm.envUint("FOUNDRY_PRIVATE_KEY");
        address reactor = vm.envAddress("FOUNDRY_SWAPROUTER02EXECUTOR_DEPLOY_REACTOR");
        address whitelistedCaller = vm.envAddress("FOUNDRY_SWAPROUTER02EXECUTOR_DEPLOY_WHITELISTED_CALLER");
        address owner = vm.envAddress("FOUNDRY_SWAPROUTER02EXECUTOR_DEPLOY_OWNER");
        address swapRouter02 = vm.envAddress("FOUNDRY_SWAPROUTER02EXECUTOR_DEPLOY_SWAPROUTER02");

        vm.startBroadcast(privateKey);
        executor = new SwapRouter02Executor{salt: 0x00}(whitelistedCaller, reactor, owner, swapRouter02);
        vm.stopBroadcast();

        console2.log("SwapRouter02Executor", address(executor));
        console2.log("owner", executor.owner());
    }
}
