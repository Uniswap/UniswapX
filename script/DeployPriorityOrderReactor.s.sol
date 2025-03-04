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
        // - Unichain: 0x00000006021a6Bce796be7ba509BBBA71e956e37 (salt: 0x6091db2522bec235454e50e498dc85cd015793826663f960074de69fee448dc4)
        PriorityOrderReactor reactor = new PriorityOrderReactor{
            salt: 0x6091db2522bec235454e50e498dc85cd015793826663f960074de69fee448dc4
        }(IPermit2(PERMIT2), owner);
        //
        console2.log("init code hash"); 
        console2.logBytes32(keccak256(abi.encodePacked(type(PriorityOrderReactor).creationCode, abi.encode(PERMIT2, owner))));
        console2.log("Reactor", address(reactor));

        OrderQuoter quoter = new OrderQuoter{salt: 0x00}();
        console2.log("Quoter", address(quoter));

        vm.stopBroadcast();

        return PriorityOrderReactorDeployment(IPermit2(PERMIT2), reactor, quoter);
    }
}
