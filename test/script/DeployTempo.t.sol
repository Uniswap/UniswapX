// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {V3DutchOrderReactor} from "../../src/reactors/V3DutchOrderReactor.sol";
import {OrderQuoter} from "../../src/lens/OrderQuoter.sol";
import {DeployDutchV3} from "../../script/DeployDutchV3.s.sol";
import {DeployOrderQuoter} from "../../script/DeployOrderQuoter.s.sol";

/// @notice Tempo (chainId 4217) deploy-script invariants.
///
/// The Tempo deployment scripts pin a specific deployed address (EXPECTED_REACTOR /
/// EXPECTED_QUOTER) that was produced by mining a CREATE2 salt against a specific
/// initcode hash. If the contract's bytecode drifts (compiler upgrade, source
/// change, metadata trailer change, etc.) the salt no longer produces the pinned
/// address — and the script's runtime invariant assertion would fail at deploy
/// time, after the deployer has already paid mainnet gas to discover the
/// mismatch.
///
/// These tests catch that drift at PR time. If they fail, re-mine the salt with
/// create2crunch using the new initcode hash and update the SALT + EXPECTED_*
/// constants in the corresponding deploy script.
contract DeployTempoTest is Test {
    address constant TEMPO_PROTOCOL_FEE_OWNER = 0x2BAD8182C09F50c8318d769245beA52C32Be46CD;
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    function _computeCreate2(bytes32 salt, bytes32 initcodeHash, address deployer) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, initcodeHash)))));
    }

    function test_deployDutchV3_predictedAddressMatchesExpected() public {
        DeployDutchV3 d = new DeployDutchV3();
        bytes memory initcode = abi.encodePacked(
            type(V3DutchOrderReactor).creationCode, abi.encode(IPermit2(PERMIT2), TEMPO_PROTOCOL_FEE_OWNER)
        );
        address predicted = _computeCreate2(d.SALT(), keccak256(initcode), CREATE2_FACTORY);
        assertEq(
            predicted,
            d.EXPECTED_REACTOR(),
            "V3DutchOrderReactor bytecode has drifted since SALT was mined; re-mine via create2crunch and update DeployDutchV3.s.sol"
        );
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

    /// Sanity: the EXPECTED_* addresses must have the leading-zero prefix the
    /// salts were mined for. Catches a future copy-paste of an arbitrary
    /// address into EXPECTED_*.
    function test_expectedAddressesHaveZeroPrefix() public {
        DeployDutchV3 v3 = new DeployDutchV3();
        DeployOrderQuoter q = new DeployOrderQuoter();
        // V3DutchOrderReactor: target was >=4 leading zero bytes.
        assertEq(
            uint256(uint160(v3.EXPECTED_REACTOR())) >> (160 - 32), 0, "EXPECTED_REACTOR missing >=4 leading zero bytes"
        );
        // OrderQuoter: target was >=3 leading zero bytes (less hot calldata target).
        assertEq(
            uint256(uint160(q.EXPECTED_QUOTER())) >> (160 - 24), 0, "EXPECTED_QUOTER missing >=3 leading zero bytes"
        );
    }
}
