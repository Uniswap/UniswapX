// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.13;

// =============================================================================
// OrderQuoter (V3) deployment script
// -----------------------------------------------------------------------------
// Deploys the OrderQuoter lens contract used for off-chain order simulation.
// OrderQuoter has no constructor args, so the initcode is just the contract's
// creationCode. We deploy through the canonical Arachnid CREATE2 factory so the
// resulting address is portable across chains and so the salt-mined zero-prefix
// is preserved.
//
// Tempo (chainId 4217) production invocation. NOTE the gas-estimate multiplier:
// Tempo charges 1000 gas/byte for contract code deposit (vs Ethereum's 200), so
// Foundry's default gas estimate (which simulates with standard EVM rules) is
// roughly 5x too low. The 500% multiplier provides safe headroom.
//
//   forge script script/DeployOrderQuoter.s.sol \
//       --rpc-url https://rpc.tempo.xyz \
//       --broadcast \
//       --verify \
//       --gas-estimate-multiplier 500 \
//       --private-key $DEPLOYER_KEY
//
// See README.md "Tempo (chain 4217) deployment notes" for chain-specific
// quirks (ERC20-only, constant block.basefee, elevated state-creation costs).
//
// -----------------------------------------------------------------------------
// TOOLCHAIN REPRODUCIBILITY (read before re-deploying or re-mining)
// -----------------------------------------------------------------------------
// The SALT below was mined against creationCode produced by this exact
// toolchain:
//
//   - OS         : macOS (Darwin, arm64 or x86_64)
//   - forge      : v1.4.4   (foundry-rs/foundry, see foundry.toml)
//   - solc       : 0.8.30   (pinned in foundry.toml)
//   - optimizer  : enabled, 1_000_000 runs (foundry.toml [profile.default])
//
// Solc emits an IPFS multihash of the source-metadata JSON into the CBOR
// trailer of every contract's bytecode. That hash is *not* reproducible
// across host platforms: a Linux solc-0.8.30 build of these same sources
// emits a different trailer than a macOS build, so the resulting CREATE2
// address differs even though the executable bytes are byte-identical.
//
// Practical consequence: re-deploying OrderQuoter from a Linux host will
// NOT produce 0x00000000a3db63Df9078cBF3dF88B4CAdD5a7F58 — the broadcast
// will land at a different address, and downstream SDKs (which pin the
// macOS-mined address) will not resolve it. Deploy from macOS or skip the
// deployment entirely on that chain.
//
// The previous CI guard test (test/script/DeployScriptDrift.t.sol) was
// removed because Ubuntu GHA runners produce Linux bytecode that
// permanently mismatches the on-chain macOS-mined addresses across all
// already-deployed chains; the guard was unfixable without re-mining, and
// re-mining is impossible since the addresses are committed on-chain.
// =============================================================================

import "forge-std/console2.sol";
import "forge-std/Script.sol";
import {OrderQuoter} from "../src/lens/OrderQuoter.sol";

struct OrderQuoterDeployment {
    OrderQuoter quoter;
}

contract DeployOrderQuoter is Script {
    // CREATE2_FACTORY (0x4e59b44847b379578588920cA78FbF26c0B4956C) is inherited
    // from forge-std's CommonBase. It's the canonical Arachnid deterministic
    // CREATE2 deployer. We deploy *through* this factory rather than via
    // Solidity's `new Contract{salt:}` construct so the resulting address is
    // chain-portable: same SALT + same initcode produces the same address on
    // any chain we redeploy to. Verified present on Tempo via eth_getCode.

    // Salt mined via create2crunch (ECO-365), targeting >=3 leading zero bytes
    // for the OrderQuoter address. OrderQuoter is called less frequently than
    // the reactor (off-chain simulation only), so the bar is lower than the
    // reactor's >=4 leading zero bytes. Each leading zero byte saves ~12 gas
    // per zero byte of calldata each time the address is encoded.
    bytes32 public constant SALT = 0x00000000000000000000000000000000000000009a06322ea4c741ed87480020;
    address public constant EXPECTED_QUOTER = 0x00000000a3db63Df9078cBF3dF88B4CAdD5a7F58;

    function setUp() public {}

    function run() public returns (OrderQuoterDeployment memory deployment) {
        bytes memory initcode = type(OrderQuoter).creationCode;

        // Predict deployed address from CREATE2 derivation:
        //   keccak256(0xff || factory || salt || keccak256(initcode))[12:]
        address predicted = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), CREATE2_FACTORY, SALT, keccak256(initcode)))))
        );
        console2.log("Predicted quoter", predicted);
        require(
            predicted == EXPECTED_QUOTER, "Predicted address != EXPECTED_QUOTER; bytecode may have drifted since mining"
        );

        vm.startBroadcast();
        // Arachnid factory ABI: calldata = salt (32 bytes) || initcode.
        (bool ok,) = CREATE2_FACTORY.call(abi.encodePacked(SALT, initcode));
        require(ok, "CREATE2 factory deploy call failed");
        vm.stopBroadcast();

        require(predicted.code.length > 0, "No code at predicted quoter address after deploy");
        OrderQuoter quoter = OrderQuoter(payable(predicted));
        console2.log("OrderQuoter", address(quoter));

        return OrderQuoterDeployment(quoter);
    }
}
