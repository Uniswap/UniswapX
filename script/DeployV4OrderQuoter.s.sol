// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.13;

import "forge-std/console2.sol";
import "forge-std/Script.sol";
import {OrderQuoter} from "../src/v4/lens/OrderQuoter.sol";

struct V4OrderQuoterDeployment {
    OrderQuoter quoter;
}

contract DeployV4OrderQuoter is Script {
    function setUp() public {}

    function run() public returns (V4OrderQuoterDeployment memory deployment) {
        vm.startBroadcast();

        OrderQuoter quoter = new OrderQuoter{salt: 0x00}();
        console2.log("V4 OrderQuoter", address(quoter));

        vm.stopBroadcast();

        return V4OrderQuoterDeployment(quoter);
    }
}

