// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.13;

import "forge-std/console2.sol";
import "forge-std/Script.sol";
import {MultiFillerSwapRouter02Executor} from "../src/sample-executors/MultiFillerSwapRouter02Executor.sol";
import {ISwapRouter02} from "../src/external/ISwapRouter02.sol";
import {IReactor} from "../src/interfaces/IReactor.sol";

contract DeployMultiFillerExecutor is Script {
    function setUp() public {}

    function run() public returns (MultiFillerSwapRouter02Executor executor) {
        uint256 privateKey = vm.envUint("FOUNDRY_PRIVATE_KEY");
        IReactor reactor = IReactor(vm.envAddress("FOUNDRY_MULTIFILLER_REACTOR_UNICHAIN"));
        ISwapRouter02 swapRouter02 = ISwapRouter02(vm.envAddress("FOUNDRY_SWAPROUTER02_UC"));
        // can encode with cast abi-encode "foo(address[])" "[addr1, addr2, ...]"
        bytes memory encodedAddresses = vm.envBytes("FOUNDRY_MULTIFILLER_ADDRESSES_ENCODED");
        address owner = vm.envAddress("FOUNDRY_MULTIFILLER_DEPLOY_OWNER_PROD");

        address[] memory decodedAddresses = abi.decode(encodedAddresses, (address[]));

        console2.log("Owner", owner);
        console2.log("reactor", address(reactor));
        console2.log("init code hash");
        bytes memory creationCode = abi.encodePacked(
            type(MultiFillerSwapRouter02Executor).creationCode,
            abi.encode(decodedAddresses, reactor, owner, swapRouter02)
        );
        console2.logBytes32(keccak256(creationCode));

        vm.startBroadcast(privateKey);
        // UC deployment: 0x000000074A4f673619557e4028B6f076d2327AfA
        executor = new MultiFillerSwapRouter02Executor{salt: 0x6df8bfe7bd972f95e2aacb4320733e99c3c961125f069fc9d64426d8e743c201}(decodedAddresses, reactor, owner, swapRouter02);
        vm.stopBroadcast();

        console2.log("SwapRouter02Executor", address(executor));
        console2.log("owner", executor.owner());
    }
}
