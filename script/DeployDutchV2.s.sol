// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.13;

import "forge-std/console2.sol";
import "forge-std/Script.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {V2DutchOrderReactor} from "../src/reactors/V2DutchOrderReactor.sol";

struct V2DutchOrderDeployment {
    IPermit2 permit2;
    V2DutchOrderReactor reactor;
}

contract DeployDutchV2 is Script {
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    function setUp() public {}

    function run() public returns (V2DutchOrderDeployment memory deployment) {
        address owner = vm.envAddress("FOUNDRY_REACTOR_OWNER");
        console2.log("Owner", owner);
        vm.startBroadcast();

        V2DutchOrderReactor reactor = new V2DutchOrderReactor{salt: 0x00}(IPermit2(PERMIT2), owner);
        console2.log("Reactor", address(reactor));

        vm.stopBroadcast();

        return V2DutchOrderDeployment(IPermit2(PERMIT2), reactor);
    }
}
