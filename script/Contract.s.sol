// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console2.sol";
import "forge-std/Script.sol";
import {PermitPost} from "permitpost/PermitPost.sol";
import {
    DutchLimitOrderReactor
} from "../src/reactor/dutch-limit/DutchLimitOrderReactor.sol";
import {OrderQuoter} from "../src/lib/OrderQuoter.sol";
import {MockERC20} from "../test/util/mock/MockERC20.sol";

contract ContractScript is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        PermitPost permitPost = new PermitPost();
        console2.log("PermitPost", address(permitPost));

        DutchLimitOrderReactor reactor = new DutchLimitOrderReactor(address(permitPost));
        console2.log("Reactor", address(reactor));

        OrderQuoter quoter = new OrderQuoter();
        console2.log("Quoter", address(quoter));

        MockERC20 tokenIn = new MockERC20("Token A", "TA", 18);
        console2.log("tokenA", address(tokenIn));
        MockERC20 tokenOut = new MockERC20("Token B", "TB", 18);
        console2.log("tokenB", address(tokenOut));

        vm.stopBroadcast();
    }
}
