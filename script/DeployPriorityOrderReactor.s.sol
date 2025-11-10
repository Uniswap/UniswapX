// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.13;

import "forge-std/console2.sol";
import "forge-std/Script.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {PriorityOrderReactor} from "../src/reactors/PriorityOrderReactor.sol";
import {OrderQuoter} from "../src/lens/OrderQuoter.sol";
import {DeployPermit2} from "../test/util/DeployPermit2.sol";

struct PriorityOrderReactorDeployment {
    IPermit2 permit2;
    PriorityOrderReactor reactor;
    OrderQuoter quoter;
}

contract DeployPriorityOrderReactor is Script, DeployPermit2 {
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    function setUp() public {}

    function run() public returns (PriorityOrderReactorDeployment memory deployment) {
        address owner = vm.envAddress("FOUNDRY_REACTOR_OWNER");

        vm.startBroadcast();
        if (PERMIT2.code.length == 0) {
            deployPermit2();
        }

        // will deploy to:
        // - BASE: 0x000000001Ec5656dcdB24D90DFa42742738De729 (salt: 0xb0059e9187daac70f2c765cfc99a03f9bf4321c11b7ab784ee3e310292724c18)
        PriorityOrderReactor reactor = new PriorityOrderReactor{
            salt: 0xb0059e9187daac70f2c765cfc99a03f9bf4321c11b7ab784ee3e310292724c18
        }(
            IPermit2(PERMIT2), owner
        );
        console2.log("Reactor", address(reactor));

        OrderQuoter quoter = new OrderQuoter{salt: 0x00}();
        console2.log("Quoter", address(quoter));

        vm.stopBroadcast();

        return PriorityOrderReactorDeployment(IPermit2(PERMIT2), reactor, quoter);
    }
}
