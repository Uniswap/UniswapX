// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console2.sol";
import "forge-std/Script.sol";
import {SwapRouter02Executor} from "../src/sample-executors/SwapRouter02Executor.sol";

contract DeploySwapRouter02Executor is Script {
    function setUp() public {}

    function run() public returns (SwapRouter02Executor executor) {
        uint256 privateKey = vm.envUint("FOUNDRY_PRIVATE_KEY");
        address deployer = vm.addr(privateKey);
        address reactor = address(0);

        vm.startBroadcast(privateKey);
        executor =
        new UniswapV3Executor{salt: 0x00}(address(0), address(0), address(0), 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);
        vm.stopBroadcast();

        console2.log("SwapRouter02Executor", address(executor));
        console2.log("owner", executor.owner());
    }
}
