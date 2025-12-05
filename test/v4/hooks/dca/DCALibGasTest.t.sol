// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

import {DCALib} from "src/v4/hooks/dca/DCALib.sol";
import {DCAOrderCosignerData} from "src/v4/hooks/dca/DCAStructs.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

/// @notice Mock ERC1271 wallet for testing smart contract signature validation
contract MockERC1271Wallet is IERC1271 {
    address public owner;

    constructor(address _owner) {
        owner = _owner;
    }

    function isValidSignature(bytes32 hash, bytes memory signature) external view override returns (bytes4) {
        // Recover the signer from the signature
        (uint8 v, bytes32 r, bytes32 s) = abi.decode(signature, (uint8, bytes32, bytes32));
        address recovered = ecrecover(hash, v, r, s);

        // If the recovered address matches the owner, return the magic value
        if (recovered == owner) {
            return IERC1271.isValidSignature.selector;
        }
        return bytes4(0);
    }
}

/// @title DCALibGasTest
/// @notice Gas benchmarking tests for DCALib.isValidSignature function
/// @dev These tests measure gas consumption for EOA and ERC-1271 signature validation
contract DCALibGasTest is Test {
    uint256 private constant PK = 0xAAAAA;
    address private signer;

    function setUp() public {
        signer = vm.addr(PK);
        vm.chainId(1);
    }

    function _domainSeparator() internal view returns (bytes32) {
        return DCALib.computeDomainSeparator(address(this));
    }

    function _createCosignerData() internal view returns (DCAOrderCosignerData memory) {
        return
            DCAOrderCosignerData({
                swapper: signer, nonce: 42, execAmount: 100 ether, limitAmount: 95 ether, orderNonce: 5
            });
    }

    /// forge-config: default.isolate = true
    /// @notice Gas benchmark: EOA signature validation (ECDSA path)
    function testGas_isValidSignature_EOA() public {
        bytes32 domainSeparator = _domainSeparator();
        DCAOrderCosignerData memory cosignerData = _createCosignerData();

        // Hash and sign
        bytes32 structHash = DCALib.hashCosignerData(cosignerData);
        bytes32 digest = DCALib.digest(domainSeparator, structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PK, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        // Measure gas for EOA signature validation
        bool isValid = DCALib.isValidSignature(signer, digest, sig);
        vm.snapshotGasLastCall("isValidSignature_EOA");
        require(isValid, "EOA signature should be valid");
    }

    /// forge-config: default.isolate = true
    /// @notice Gas benchmark: Smart contract wallet signature validation (EIP-1271 path)
    function testGas_isValidSignature_ERC1271() public {
        bytes32 domainSeparator = _domainSeparator();

        // Deploy mock ERC1271 wallet with signer as owner
        MockERC1271Wallet wallet = new MockERC1271Wallet(signer);

        DCAOrderCosignerData memory cosignerData = _createCosignerData();

        // Hash and sign with owner's key
        bytes32 structHash = DCALib.hashCosignerData(cosignerData);
        bytes32 digest = DCALib.digest(domainSeparator, structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PK, digest);

        // Encode signature for ERC1271 (v, r, s format)
        bytes memory sig = abi.encode(v, r, s);

        // Measure gas for ERC1271 signature validation
        bool isValid = DCALib.isValidSignature(address(wallet), digest, sig);
        vm.snapshotGasLastCall("isValidSignature_ERC1271");
        require(isValid, "ERC1271 signature should be valid");
    }

    /// forge-config: default.isolate = true
    /// @notice Gas benchmark: Invalid EOA signature
    function testGas_isValidSignature_EOA_Invalid() public {
        bytes32 domainSeparator = _domainSeparator();
        DCAOrderCosignerData memory cosignerData = _createCosignerData();

        // Hash and sign with WRONG key
        bytes32 structHash = DCALib.hashCosignerData(cosignerData);
        bytes32 digest = DCALib.digest(domainSeparator, structHash);
        uint256 wrongKey = 0x99999;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongKey, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        // Measure gas for invalid EOA signature validation
        bool isValid = DCALib.isValidSignature(signer, digest, sig);
        vm.snapshotGasLastCall("isValidSignature_EOA_Invalid");
        require(!isValid, "Invalid EOA signature should fail");
    }

    /// forge-config: default.isolate = true
    /// @notice Gas benchmark: Invalid ERC1271 signature
    function testGas_isValidSignature_ERC1271_Invalid() public {
        bytes32 domainSeparator = _domainSeparator();

        // Deploy mock ERC1271 wallet with signer as owner
        MockERC1271Wallet wallet = new MockERC1271Wallet(signer);

        DCAOrderCosignerData memory cosignerData = _createCosignerData();

        // Hash and sign with WRONG key
        bytes32 structHash = DCALib.hashCosignerData(cosignerData);
        bytes32 digest = DCALib.digest(domainSeparator, structHash);
        uint256 wrongKey = 0x88888;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongKey, digest);

        // Encode signature for ERC1271 (v, r, s format)
        bytes memory sig = abi.encode(v, r, s);

        // Measure gas for invalid ERC1271 signature validation
        bool isValid = DCALib.isValidSignature(address(wallet), digest, sig);
        vm.snapshotGasLastCall("isValidSignature_ERC1271_Invalid");
        require(!isValid, "Invalid ERC1271 signature should fail");
    }
}
