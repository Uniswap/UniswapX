// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.13;

// =============================================================================
// V3DutchOrderReactor deployment script
// -----------------------------------------------------------------------------
// Prereqs:
//   - Permit2 must already be deployed at the canonical address
//     0x000000000022D473030F116dDEE9F6B43aC78BA3 on the target chain. This is
//     verified to be present on Tempo (chainId 4217). The reactor constructor
//     binds to this address, so permit2 must exist before this script runs.
//
// Required env vars:
//   - FOUNDRY_REACTOR_OWNER : address that will own the deployed reactor.
//
// Tempo (chainId 4217) example invocation (for testing only — production
// deploys go through the /contracts orchestration repo):
//
//   forge script script/DeployDutchV3.s.sol \
//       --rpc-url https://rpc.tempo.xyz \
//       --broadcast \
//       --private-key $DEPLOYER_KEY
//
// See README.md "Tempo (chain 4217) deployment notes" for chain-specific
// quirks (ERC20-only, constant block.basefee, etc.).
// =============================================================================

import "forge-std/console2.sol";
import "forge-std/Script.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {V3DutchOrderReactor} from "../src/reactors/V3DutchOrderReactor.sol";

struct V3DutchOrderDeployment {
    IPermit2 permit2;
    V3DutchOrderReactor reactor;
}

contract DeployDutchV3 is Script {
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    function setUp() public {}

    function run() public returns (V3DutchOrderDeployment memory deployment) {
        address owner = vm.envAddress("FOUNDRY_REACTOR_OWNER");
        console2.log("Owner", owner);
        vm.startBroadcast();

        V3DutchOrderReactor reactor = new V3DutchOrderReactor{salt: 0x00}(IPermit2(PERMIT2), owner);
        console2.log("Reactor", address(reactor));

        vm.stopBroadcast();

        return V3DutchOrderDeployment(IPermit2(PERMIT2), reactor);
    }
}
