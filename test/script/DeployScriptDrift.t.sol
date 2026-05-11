// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {OrderQuoter} from "../../src/lens/OrderQuoter.sol";
import {V3DutchOrderReactor} from "../../src/reactors/V3DutchOrderReactor.sol";
import {DeployOrderQuoter} from "../../script/DeployOrderQuoter.s.sol";

/// @notice Drift-detection for the deploy scripts' pinned CREATE2 outputs.
///
/// `DeployOrderQuoter.s.sol` keeps SALT + EXPECTED_QUOTER as `public constant`s
/// because OrderQuoter has no constructor args — its initcode is its
/// creationCode and is therefore chain-agnostic.
///
/// `DeployDutchV3.s.sol` is multi-chain: per-chain owner from
/// `PoolManager.owner()`; per-chain SALT + EXPECTED from
/// `playbook/chains/salts.json`. The per-chain test below iterates that
/// registry and asserts each chain's `(salt, owner)` reproduces the listed
/// `expectedReactor` against current bytecode.
///
/// Either way, if bytecode drifts (compiler upgrade, source change, metadata
/// trailer shift) the salts no longer produce the pinned addresses — and the
/// deploy-time invariant assertion would fail after the deployer has already
/// paid mainnet gas. These tests catch the drift at PR time.
contract DeployScriptDriftTest is Test {
    using stdJson for string;

    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    function _computeCreate2(bytes32 salt, bytes32 initcodeHash, address deployer) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, initcodeHash)))));
    }

    function test_deployOrderQuoter_predictedAddressMatchesExpected() public {
        DeployOrderQuoter d = new DeployOrderQuoter();
        bytes memory initcode = type(OrderQuoter).creationCode;
        address predicted = _computeCreate2(d.SALT(), keccak256(initcode), CREATE2_FACTORY);
        assertEq(
            predicted,
            d.EXPECTED_QUOTER(),
            "OrderQuoter bytecode has drifted since SALT was mined; re-mine via create2crunch and update DeployOrderQuoter.s.sol"
        );
    }

    /// Sanity: EXPECTED_QUOTER must have the leading-zero prefix the salt was
    /// mined for. Catches a copy-paste of an arbitrary address into the const.
    function test_expectedQuoterHasZeroPrefix() public {
        DeployOrderQuoter q = new DeployOrderQuoter();
        // OrderQuoter: target was >=3 leading zero bytes.
        assertEq(
            uint256(uint160(q.EXPECTED_QUOTER())) >> (160 - 24), 0, "EXPECTED_QUOTER missing >=3 leading zero bytes"
        );
    }

    /// For every chain in `playbook/chains/salts.json` with a populated
    /// `(owner, salt, expectedReactor)` tuple, assert the CREATE2 derivation
    /// against the current V3DutchOrderReactor bytecode reproduces
    /// `expectedReactor`. Chains with null fields (e.g. v4-PoolManager-less
    /// chains awaiting deploy) are skipped via try/catch around the parse.
    function test_deployV3Reactor_perChainPredictedMatchesExpected() public {
        string memory json = vm.readFile("playbook/chains/salts.json");
        string[] memory chainIds = vm.parseJsonKeys(json, ".chains");

        bytes memory creationCode = type(V3DutchOrderReactor).creationCode;
        uint256 checked;

        for (uint256 i = 0; i < chainIds.length; i++) {
            string memory base = string.concat(".chains.", chainIds[i]);
            address owner;
            bytes32 salt;
            address expected;
            string memory name;
            try this._readChain(json, base) returns (bool, address o, bytes32 s, address e, string memory n) {
                owner = o; salt = s; expected = e; name = n;
            } catch {
                continue;
            }

            bytes memory initcode = abi.encodePacked(creationCode, abi.encode(IPermit2(PERMIT2), owner));
            address predicted = _computeCreate2(salt, keccak256(initcode), CREATE2_FACTORY);

            assertEq(
                predicted,
                expected,
                string.concat(
                    "V3DutchOrderReactor drift on chain ",
                    name,
                    " (",
                    chainIds[i],
                    "): bytecode no longer produces salts.json expectedReactor - re-mine via scripts/mine-salt.sh"
                )
            );
            checked++;
        }

        // Guard against the JSON parsing silently skipping every entry (would
        // make the test green for the wrong reason). At least one rollout
        // chain should always have a populated tuple.
        assertGt(checked, 0, "no chains had populated (salt, owner, expectedReactor) - JSON parsing likely broken");
    }

    /// External helper so individual parse failures (e.g. salt: null on a
    /// deferred chain) can be caught with try/catch without aborting the
    /// whole test. `external` is required because Solidity try/catch only
    /// works on external calls.
    function _readChain(string memory json, string memory base)
        external
        view
        returns (bool ok, address owner, bytes32 salt, address expected, string memory name)
    {
        owner = json.readAddress(string.concat(base, ".owner"));
        salt = json.readBytes32(string.concat(base, ".salt"));
        expected = json.readAddress(string.concat(base, ".expectedReactor"));
        name = json.readString(string.concat(base, ".name"));
        ok = true;
    }
}
