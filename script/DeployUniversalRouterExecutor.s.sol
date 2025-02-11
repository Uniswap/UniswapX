// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.13;

import "forge-std/console2.sol";
import "forge-std/Script.sol";
import {UniversalRouterExecutor} from "../src/sample-executors/UniversalRouterExecutor.sol";
import {IReactor} from "../src/interfaces/IReactor.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";

contract DeployUniversalRouterExecutor is Script {
    function setUp() public {}

    function run() public returns (UniversalRouterExecutor executor) {
        uint256 privateKey = vm.envUint("FOUNDRY_PRIVATE_KEY");
        IReactor reactor = IReactor(vm.envAddress("FOUNDRY_UNIVERSALROUTEREXECUTOR_DEPLOY_REACTOR"));
        // can encode with cast abi-encode "foo(address[])" "[addr1, addr2, ...]"
        bytes memory encodedAddresses =
            vm.envBytes("FOUNDRY_UNIVERSALROUTEREXECUTOR_DEPLOY_WHITELISTED_CALLERS_ENCODED");
        address owner = vm.envAddress("FOUNDRY_UNIVERSALROUTEREXECUTOR_DEPLOY_OWNER");
        address universalRouter = vm.envAddress("FOUNDRY_UNIVERSALROUTEREXECUTOR_DEPLOY_UNIVERSALROUTER");
        IPermit2 permit2 = IPermit2(vm.envAddress("FOUNDRY_UNIVERSALROUTEREXECUTOR_DEPLOY_PERMIT2"));

        address[] memory decodedAddresses = abi.decode(encodedAddresses, (address[]));

        vm.startBroadcast(privateKey);
        executor = new UniversalRouterExecutor{salt: 0x00}(decodedAddresses, reactor, owner, universalRouter, permit2);
        vm.stopBroadcast();

        console2.log("UniversalRouterExecutor", address(executor));
        console2.log("owner", executor.owner());
    }
}
