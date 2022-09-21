// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console2.sol";
import "forge-std/Script.sol";
import {PermitPost} from "permitpost/PermitPost.sol";
import {DutchLimitOrderReactor} from "../src/reactors/dutch-limit/DutchLimitOrderReactor.sol";
import {DirectTakerExecutor} from "../src/sample-executors/DirectTakerExecutor.sol";
import {OrderQuoter} from "../src/lens/OrderQuoter.sol";
import {MockERC20} from "../test/util/mock/MockERC20.sol";

struct DutchLimitDeployment {
    PermitPost permitPost;
    DutchLimitOrderReactor reactor;
    OrderQuoter quoter;
    DirectTakerExecutor executor;
    MockERC20 tokenIn;
    MockERC20 tokenOut;
}

contract DeployDutchLimit is Script {
    function setUp() public {}

    function run() public returns (DutchLimitDeployment memory deployment) {
        vm.startBroadcast();
        PermitPost permitPost = new PermitPost{salt: 0x00}();
        console2.log("PermitPost", address(permitPost));

        DutchLimitOrderReactor reactor = new DutchLimitOrderReactor{salt: 0x00}(address(permitPost));
        console2.log("Reactor", address(reactor));

        OrderQuoter quoter = new OrderQuoter{salt: 0x00}();
        console2.log("Quoter", address(quoter));

        DirectTakerExecutor executor = new DirectTakerExecutor{salt: 0x00}();
        console2.log("Executor", address(executor));

        MockERC20 tokenIn = new MockERC20{salt: 0x00}("Token A", "TA", 18);
        console2.log("tokenA", address(tokenIn));
        MockERC20 tokenOut = new MockERC20{salt: 0x00}("Token B", "TB", 18);
        console2.log("tokenB", address(tokenOut));

        vm.stopBroadcast();

        return DutchLimitDeployment(permitPost, reactor, quoter, executor, tokenIn, tokenOut);
    }
}
