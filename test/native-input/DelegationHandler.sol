// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {ICalibur} from "../../lib/calibur/src/interfaces/ICalibur.sol";
import {Constants} from "../../lib/calibur/test/utils/Constants.sol";
import {EntryPoint} from "../../lib/calibur/lib/account-abstraction/contracts/core/EntryPoint.sol";
import {TestKeyManager, TestKey} from "../../lib/calibur/test/utils/TestKeyManager.sol";
import {KeyType} from "../../lib/calibur/src/libraries/KeyLib.sol";

contract DelegationHandler is Test {
    ICalibur public calibur;
    uint256 signerPrivateKey = 0xa11ce;
    address signer = vm.addr(signerPrivateKey);
    TestKey signerTestKey = TestKey(KeyType.Secp256k1, abi.encode(signer), signerPrivateKey);
    EntryPoint public entryPoint;
    ICalibur public signerAccount;

    // Override to use the correct path for vm.getCode when running from parent project
    function setUpDelegation() public {
        calibur = ICalibur(create2(vm.getCode("lib/calibur/out/CaliburEntry.sol/CaliburEntry.json"), bytes32(0)));
        _delegate(signer, address(calibur));
        signerAccount = ICalibur(signer);

        vm.etch(Constants.ENTRY_POINT_V_0_8, Constants.ENTRY_POINT_V_0_8_CODE);
        vm.label(Constants.ENTRY_POINT_V_0_8, "EntryPoint");

        entryPoint = EntryPoint(payable(Constants.ENTRY_POINT_V_0_8));
    }

    function create2(bytes memory initcode, bytes32 salt) internal returns (address contractAddress) {
        assembly {
            contractAddress := create2(0, add(initcode, 32), mload(initcode), salt)
            if iszero(contractAddress) {
                let ptr := mload(0x40)
                let errorSize := returndatasize()
                returndatacopy(ptr, 0, errorSize)
                revert(ptr, errorSize)
            }
        }
    }

    function _delegate(address _signer, address _implementation) internal {
        vm.etch(_signer, bytes.concat(hex"ef0100", abi.encodePacked(_implementation)));
        require(_signer.code.length > 0, "signer not delegated");
    }
}
