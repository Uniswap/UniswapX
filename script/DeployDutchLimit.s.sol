// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console2.sol";
import "forge-std/Script.sol";
import {Permit2} from "permit2/Permit2.sol";
import {DutchLimitOrderReactor} from "../src/reactors/DutchLimitOrderReactor.sol";
import {OrderQuoter} from "../src/lens/OrderQuoter.sol";
import {MockERC20} from "../test/util/mock/MockERC20.sol";

struct DutchLimitDeployment {
    Permit2 permit2;
    DutchLimitOrderReactor reactor;
    OrderQuoter quoter;
    MockERC20 tokenIn;
    MockERC20 tokenOut;
}

contract DeployDutchLimit is Script {
    address constant UNI_TIMELOCK = 0x1a9C8182C09F50C8318d769245beA52c32BE35BC;
    uint256 constant PROTOCOL_FEES_BPS = 5000;

    function setUp() public {}

    function run() public returns (DutchLimitDeployment memory deployment) {
        vm.startBroadcast();
        Permit2 permit2 = new Permit2{salt: 0x00}();
        console2.log("Permit2", address(permit2));

        DutchLimitOrderReactor reactor =
            new DutchLimitOrderReactor{salt: 0x00}(address(permit2), PROTOCOL_FEES_BPS, UNI_TIMELOCK);
        console2.log("Reactor", address(reactor));

        OrderQuoter quoter = new OrderQuoter{salt: 0x00}();
        console2.log("Quoter", address(quoter));

        MockERC20 tokenIn = new MockERC20{salt: 0x00}("Token A", "TA", 18);
        console2.log("tokenA", address(tokenIn));
        MockERC20 tokenOut = new MockERC20{salt: 0x00}("Token B", "TB", 18);
        console2.log("tokenB", address(tokenOut));

        vm.stopBroadcast();

        return DutchLimitDeployment(permit2, reactor, quoter, tokenIn, tokenOut);
    }
}
