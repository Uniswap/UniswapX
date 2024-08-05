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
    address constant UNI_TIMELOCK = 0x1a9C8182C09F50C8318d769245beA52c32BE35BC;

    function setUp() public {}

    function run() public returns (PriorityOrderReactorDeployment memory deployment) {
        vm.startBroadcast();
        if (PERMIT2.code.length == 0) {
            deployPermit2();
        }

        // will deploy to: 0x00000000e990A30496431710d6B58384a603b45c
        PriorityOrderReactor reactor = new PriorityOrderReactor{
            salt: 0xee73c108815b7b841a11030c53600e3a1d8a5dd2d42966e386e5107a3da56e81
        }(IPermit2(PERMIT2), UNI_TIMELOCK);
        console2.log("Reactor", address(reactor));

        OrderQuoter quoter = new OrderQuoter{salt: 0x00}();
        console2.log("Quoter", address(quoter));

        vm.stopBroadcast();

        return PriorityOrderReactorDeployment(IPermit2(PERMIT2), reactor, quoter);
    }
}
