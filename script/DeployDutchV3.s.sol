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
//   - The canonical Arachnid CREATE2 deployer at 0x4e59b44847b379578588920cA78FbF26c0B4956C
//     must be deployed on the target chain (verified present on Tempo).
//
// Required env vars:
//   - FOUNDRY_REACTOR_OWNER : address that will own the deployed reactor.
//                             For Tempo this MUST match the address baked into
//                             the mined SALT (see EXPECTED_REACTOR below);
//                             changing it produces a different address and the
//                             post-deploy invariant assertion will fail.
//
// Tempo (chainId 4217) production invocation:
//
//   FOUNDRY_REACTOR_OWNER=0x2bad8182c09f50c8318d769245bea52c32be46cd \
//   forge script script/DeployDutchV3.s.sol \
//       --rpc-url https://rpc.tempo.xyz \
//       --broadcast \
//       --private-key $DEPLOYER_KEY
//
// (FOUNDRY_REACTOR_OWNER above matches the protocolFeeOwner used on
// Arbitrum One — see deployments records in the Uniswap contracts repo.)
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

    // CREATE2_FACTORY (0x4e59b44847b379578588920cA78FbF26c0B4956C) is inherited
    // from forge-std's CommonBase. It's the canonical Arachnid deterministic
    // CREATE2 deployer; deployed at the same address on every supported EVM
    // chain. We deploy the reactor *through* this factory (rather than via
    // Solidity's `new Contract{salt:}` construct, which would use the
    // broadcaster EOA as the deployer) so the resulting address is portable:
    // the same SALT + same initcode produces the same address on any chain we
    // redeploy to. Verified present on Tempo via eth_getCode.

    // Salt mined via create2crunch (ECO-365), targeting >=4 leading zero bytes
    // for the V3DutchOrderReactor address. Paired with the canonical CREATE2
    // factory and the production constructor args (Permit2 + protocolFeeOwner
    // = 0x2bad8182c09f50c8318d769245bea52c32be46cd) it produces EXPECTED_REACTOR
    // below.
    //
    // 4 leading zero bytes + 1 additional zero byte in the body = 5 total zero
    // bytes, saving ~12 gas per zero byte of calldata each time the reactor
    // address is encoded (every UniswapX fill encodes the reactor in the
    // order's Permit2 witness).
    bytes32 constant SALT = 0x0000000000000000000000000000000000000000e931b28b35b132822db301c0;
    address constant EXPECTED_REACTOR = 0x000000005aF66799D1a6317714D66800f9CA1406;

    function setUp() public {}

    function run() public returns (V3DutchOrderDeployment memory deployment) {
        address owner = vm.envAddress("FOUNDRY_REACTOR_OWNER");
        console2.log("Owner", owner);

        // Build the V3DutchOrderReactor initcode the canonical CREATE2 factory
        // expects: creationCode || abi.encode(constructor args).
        bytes memory initcode =
            abi.encodePacked(type(V3DutchOrderReactor).creationCode, abi.encode(IPermit2(PERMIT2), owner));

        // Predict the deployed address from CREATE2 derivation:
        //   keccak256(0xff || factory || salt || keccak256(initcode))[12:]
        // Assert it matches the address mined for our production constructor
        // args. If FOUNDRY_REACTOR_OWNER doesn't match what we mined for, this
        // assertion will fail before any tx is broadcast.
        address predicted = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), CREATE2_FACTORY, SALT, keccak256(initcode)))))
        );
        console2.log("Predicted reactor", predicted);
        require(
            predicted == EXPECTED_REACTOR,
            "Predicted address != EXPECTED_REACTOR; FOUNDRY_REACTOR_OWNER may not match the mined args"
        );

        vm.startBroadcast();
        // Arachnid factory ABI: calldata = salt (32 bytes) || initcode.
        // Factory CREATE2-deploys and returns the deployed address; we ignore
        // the return value and rely on the CREATE2 derivation we already
        // verified, plus the post-deploy code-length check below.
        (bool ok,) = CREATE2_FACTORY.call(abi.encodePacked(SALT, initcode));
        require(ok, "CREATE2 factory deploy call failed");
        vm.stopBroadcast();

        require(predicted.code.length > 0, "No code at predicted reactor address after deploy");
        V3DutchOrderReactor reactor = V3DutchOrderReactor(payable(predicted));
        console2.log("Reactor", address(reactor));

        return V3DutchOrderDeployment(IPermit2(PERMIT2), reactor);
    }
}
