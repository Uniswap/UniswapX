// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {OrderQuoter} from "../../src/lens/OrderQuoter.sol";
import {DeployOrderQuoter} from "../../script/DeployOrderQuoter.s.sol";

/// @notice Drift-detection for the deploy scripts' pinned CREATE2 outputs.
///
/// `DeployOrderQuoter.s.sol` keeps SALT + EXPECTED_QUOTER as `public constant`s
/// because OrderQuoter has no constructor args — its initcode is its
/// creationCode and is therefore chain-agnostic. If the bytecode drifts
/// (compiler upgrade, source change, metadata trailer shift), the salt no
/// longer produces the pinned address — and the deploy-time invariant
/// assertion would fail after the deployer has already paid mainnet gas. This
/// test catches that drift at PR time.
///
/// `DeployDutchV3.s.sol` is multi-chain (per-chain owner from PoolManager.owner();
/// per-chain SALT + EXPECTED from `playbook/chains/salts.json`) so its drift
/// check is performed per-chain by `scripts/deploy-v3-multichain.sh` via the
/// in-script `predicted == V3_REACTOR_EXPECTED` runtime assertion against the
/// runtime initcode and runtime owner. There's no single salt for the V3 test
/// to assert against here.
contract DeployScriptDriftTest is Test {
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
}
