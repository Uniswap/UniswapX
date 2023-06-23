// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.13;

import "forge-std/console2.sol";
import "forge-std/Script.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {ExclusiveDutchOrderReactor} from "../src/reactors/ExclusiveDutchOrderReactor.sol";
import {OrderQuoter} from "../src/lens/OrderQuoter.sol";
import {DeployPermit2} from "../test/util/DeployPermit2.sol";
import {MockERC20} from "../test/util/mock/MockERC20.sol";

struct ExclusiveDutchDeployment {
    IPermit2 permit2;
    ExclusiveDutchOrderReactor reactor;
    OrderQuoter quoter;
    MockERC20 tokenIn;
    MockERC20 tokenOut;
}

contract DeployExclusiveDutch is Script, DeployPermit2 {
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant UNI_TIMELOCK = 0x1a9C8182C09F50C8318d769245beA52c32BE35BC;

    function setUp() public {}

    function run() public returns (ExclusiveDutchDeployment memory deployment) {
        vm.startBroadcast();
        if (PERMIT2.code.length == 0) {
            deployPermit2();
        }

        ExclusiveDutchOrderReactor reactor = new ExclusiveDutchOrderReactor{salt: 0x00}(IPermit2(PERMIT2), UNI_TIMELOCK);
        console2.log("Reactor", address(reactor));

        OrderQuoter quoter = new OrderQuoter{salt: 0x00}();
        console2.log("Quoter", address(quoter));

        MockERC20 tokenIn = new MockERC20{salt: 0x00}("Token A", "TA", 18);
        console2.log("tokenA", address(tokenIn));
        MockERC20 tokenOut = new MockERC20{salt: 0x00}("Token B", "TB", 18);
        console2.log("tokenB", address(tokenOut));

        vm.stopBroadcast();

        return ExclusiveDutchDeployment(IPermit2(PERMIT2), reactor, quoter, tokenIn, tokenOut);
    }
}
