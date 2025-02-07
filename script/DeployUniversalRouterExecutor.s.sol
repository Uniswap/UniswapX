// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.13;

import "forge-std/console2.sol";
import "forge-std/Script.sol";
import {UniversalRouterExecutor} from "../src/sample-executors/UniversalRouterExecutor.sol";
import {IReactor} from "../src/interfaces/IReactor.sol";

contract DeployUniversalRouterExecutor is Script {
    function setUp() public {}

    function run() public returns (UniversalRouterExecutor executor) {
        uint256 privateKey = vm.envUint("FOUNDRY_PRIVATE_KEY");
        IReactor reactor = IReactor(vm.envAddress("FOUNDRY_UNIVERSALROUTEREXECUTOR_DEPLOY_REACTOR"));
        address whitelistedCaller = vm.envAddress("FOUNDRY_UNIVERSALROUTEREXECUTOR_DEPLOY_WHITELISTED_CALLER");
        address owner = vm.envAddress("FOUNDRY_UNIVERSALROUTEREXECUTOR_DEPLOY_OWNER");
        address universalRouter = vm.envAddress("FOUNDRY_UNIVERSALROUTEREXECUTOR_DEPLOY_UNIVERSALROUTER");

        vm.startBroadcast(privateKey);
        executor = new UniversalRouterExecutor{salt: 0x00}(whitelistedCaller, reactor, owner, universalRouter);
        vm.stopBroadcast();

        console2.log("UniversalRouterExecutor", address(executor));
        console2.log("owner", executor.owner());
    }
}
