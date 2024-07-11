// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {CosignerLib} from "../../src/lib/CosignerLib.sol";

/// @notice mock contract to test CosignerLib functionality
contract MockCosignerLibContract {
    function verify(address cosigner, bytes32 data, bytes memory cosignature) public pure {
        CosignerLib.verify(cosigner, data, cosignature);
    }
}

contract CosignerLibTest is Test {
    uint256 cosignerPrivateKey = 0x123;
    
    MockCosignerLibContract mockCosignerLibContract = new MockCosignerLibContract();

    /// @notice verify that a cosignature is valid for a given cosigner and data
    function testVerifyCosignature() public view {
        address cosigner = vm.addr(cosignerPrivateKey);
        bytes32 data = keccak256(abi.encodePacked("data"));
        mockCosignerLibContract.verify(cosigner, data, sign(data));
    }

    /// @notice must revert if the data does not match what was signed over
    function testRevertsInvalidData() public {
        address cosigner = vm.addr(cosignerPrivateKey);
        bytes32 data = keccak256(abi.encodePacked("data"));
        bytes memory sig = sign(keccak256(abi.encodePacked("invalidData")));

        vm.expectRevert(CosignerLib.InvalidCosignature.selector);
        mockCosignerLibContract.verify(cosigner, data, sig);
    }

    /// @notice must revert if the cosignature is invalid
    function testRevertsInvalidCosignature() public {
        address cosigner = vm.addr(cosignerPrivateKey);
        bytes32 data = keccak256(abi.encodePacked("data"));
        bytes memory invalidSig = bytes.concat(keccak256("invalidSignature"), keccak256("invalidSignature"), hex"33");

        vm.expectRevert(CosignerLib.InvalidCosignature.selector);
        mockCosignerLibContract.verify(cosigner, data, invalidSig);
    }

    /// @notice must revert if ecrecover returns address(0)
    function testRevertsAddressZeroSigner() public {
        address cosigner = vm.addr(cosignerPrivateKey);
        bytes32 data = keccak256(abi.encodePacked("data"));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(cosignerPrivateKey, data);
        v = 0;
        bytes memory sig = bytes.concat(r, s, bytes1(v));

        assertEq(ecrecover(data, v, r, s), address(0));

        vm.expectRevert(CosignerLib.InvalidCosignature.selector);
        mockCosignerLibContract.verify(cosigner, data, sig);
    }

    function sign(bytes32 hash) internal view returns (bytes memory sig) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(cosignerPrivateKey, hash);
        sig = bytes.concat(r, s, bytes1(v));
    }
}