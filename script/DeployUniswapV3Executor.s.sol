// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console2.sol";
import "forge-std/Script.sol";
import {UniswapV3Executor} from "../src/sample-executors/UniswapV3Executor.sol";

contract DeployUniswapV3Executor is Script {
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    function setUp() public {}

    function run() public returns (UniswapV3Executor executor) {
        uint256 privateKey = vm.envUint("FOUNDRY_PRIVATE_KEY");
        address deployer = vm.addr(privateKey);

        vm.startBroadcast(privateKey);
        executor = new UniswapV3Executor{salt: 0x00}(WETH, 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45, deployer);
        vm.stopBroadcast();

        console2.log("Executor", address(executor));
        console2.log("owner", executor.owner());
    }
}
