// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.13;

// =============================================================================
// V3DutchOrderReactor deployment script
// -----------------------------------------------------------------------------
// Prereqs (verified by scripts/deploy-v3-multichain.sh before invoking):
//   - Permit2 deployed at canonical 0x000000000022D473030F116dDEE9F6B43aC78BA3
//   - Canonical Arachnid CREATE2 deployer at 0x4e59b44847b379578588920cA78FbF26c0B4956C
//
// Required env vars (all three must be paired together — they only make sense
// as a tuple mined together by create2crunch):
//   FOUNDRY_REACTOR_OWNER : V3DutchOrderReactor's constructor `protocolFeeOwner`
//                           arg. The discovery flow is: read the chain's v4
//                           PoolManager, call `owner()`, use the returned
//                           address. So the V3 reactor's governance matches
//                           the AMM's per-chain.
//   V3_REACTOR_SALT       : CREATE2 salt mined for the (PERMIT2,
//                           FOUNDRY_REACTOR_OWNER) pair. bytes32 hex.
//   V3_REACTOR_EXPECTED   : the deployed address that pair produces under the
//                           canonical Arachnid factory. Pre-broadcast we
//                           assert predicted CREATE2 derivation == this; if
//                           the assertion fails, the salt was mined against
//                           a different bytecode/owner combo than what's
//                           about to be deployed.
//
// The salts table per chain lives in `playbook/chains/salts.json`; the
// multi-chain wrapper at `scripts/deploy-v3-multichain.sh` reads that file
// and exports the right values per chain. Run that wrapper rather than this
// script directly.
//
// Single-chain manual invocation (legacy / debug):
//   FOUNDRY_REACTOR_OWNER=0x... \
//   V3_REACTOR_SALT=0x... \
//   V3_REACTOR_EXPECTED=0x... \
//   forge script script/DeployDutchV3.s.sol \
//       --rpc-url <RPC> --broadcast \
//       --private-key $DEPLOYER_KEY \
//       --gas-estimate-multiplier 500
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
    // broadcaster EOA as the deployer) so chains where the (PERMIT2, owner,
    // salt) tuple matches converge on the same reactor address.

    function setUp() public {}

    function run() public returns (V3DutchOrderDeployment memory deployment) {
        // All three are paired together — they only make sense as a tuple
        // mined together by create2crunch. Read each per-deploy from env.
        address owner = vm.envAddress("FOUNDRY_REACTOR_OWNER");
        bytes32 salt = vm.envBytes32("V3_REACTOR_SALT");
        address expected = vm.envAddress("V3_REACTOR_EXPECTED");
        console2.log("ChainId  ", block.chainid);
        console2.log("Owner    ", owner);
        console2.log("Expected ", expected);

        // Optional chain-id pin: when V3_REACTOR_CHAIN_ID is set, assert we're
        // actually broadcasting on the chain the salt was mined for. Catches
        // accidentally running with the wrong --rpc-url. The multi-chain
        // wrapper sets this per chain; manual invocations may leave it unset.
        try vm.envUint("V3_REACTOR_CHAIN_ID") returns (uint256 pinnedChainId) {
            require(block.chainid == pinnedChainId, "block.chainid != V3_REACTOR_CHAIN_ID");
        } catch {}

        // Canonical-address sanity: both Permit2 and the Arachnid factory must
        // be deployed at their well-known addresses for the salt to produce
        // the predicted CREATE2 address.
        require(PERMIT2.code.length > 0, "Permit2 not deployed at canonical address on this chain");
        require(
            CREATE2_FACTORY.code.length > 0, "Arachnid CREATE2 factory not deployed at canonical address on this chain"
        );

        // Build the V3DutchOrderReactor initcode the canonical CREATE2 factory
        // expects: creationCode || abi.encode(constructor args).
        bytes memory initcode =
            abi.encodePacked(type(V3DutchOrderReactor).creationCode, abi.encode(IPermit2(PERMIT2), owner));

        // Predict deployed address from CREATE2 derivation:
        //   keccak256(0xff || factory || salt || keccak256(initcode))[12:]
        // Assert it matches the expected address from the salts table. If
        // mismatch: the salt was mined against a different (owner, bytecode)
        // tuple than what's about to be deployed — common causes are stale
        // salts.json, owner change since mining, or compiler bytecode drift.
        address predicted = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), CREATE2_FACTORY, salt, keccak256(initcode)))))
        );
        console2.log("Predicted", predicted);
        require(
            predicted == expected,
            "Predicted CREATE2 address != V3_REACTOR_EXPECTED; (owner, salt, bytecode) may have drifted since mining"
        );

        vm.startBroadcast();
        // Arachnid factory ABI: calldata = salt (32 bytes) || initcode.
        // Factory CREATE2-deploys; we ignore its return value and rely on the
        // CREATE2 derivation we already verified, plus the post-deploy
        // code-length check below.
        (bool ok,) = CREATE2_FACTORY.call(abi.encodePacked(salt, initcode));
        require(ok, "CREATE2 factory deploy call failed");
        vm.stopBroadcast();

        require(predicted.code.length > 0, "No code at predicted reactor address after deploy");
        V3DutchOrderReactor reactor = V3DutchOrderReactor(payable(predicted));
        console2.log("Reactor  ", address(reactor));

        return V3DutchOrderDeployment(IPermit2(PERMIT2), reactor);
    }
}
