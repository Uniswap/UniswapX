// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import { DCALib } from "src/v4/hooks/dca/DCALib.sol";
import { DCAIntent, PrivateIntent, OutputAllocation } from "src/v4/hooks/dca/DCAStructs.sol";

contract DCALibTest is Test {
    // deterministic test key
    uint256 private constant PK = 0xAAAAA;
    address private signer;

    string  constant NAME    = "DCAHook";
    string  constant VERSION = "1";
    uint256 constant CHAINID = 1;

    function setUp() public {
        signer = vm.addr(PK);
        vm.chainId(CHAINID);
    }

    // --- helpers ---

    function _domainSeparator(address verifying) internal view returns (bytes32) {
        return DCALib.computeDomainSeparator(verifying);
    }

    function _sampleIntent(address verifying, uint256 deadline) internal view returns (DCAIntent memory) {
        // build PrivateIntent
        PrivateIntent memory priv = PrivateIntent({
            totalInputAmount: 1000,
            exactFrequency:   3600, // 1h
            numChunks:        10,
            salt:             keccak256("test-salt"),
            oracleFeeds:      _feedIds()
        });

        // one or more output allocations
        OutputAllocation[] memory outs = new OutputAllocation[](2);
        outs[0] = OutputAllocation({ recipient: address(0xAAAAA), basisPoints: 9975 });
        outs[1] = OutputAllocation({ recipient: address(0xFFFFF), basisPoints: 25 });

        // outer struct
        return DCAIntent({
            swapper:        signer,
            nonce:          42,
            chainId:        CHAINID,
            hookAddress:    verifying,
            isExactIn:      true,
            inputToken:     address(0x1111),
            outputToken:    address(0x2222),
            cosigner:       address(0x3333),
            minPeriod:      300,
            maxPeriod:      7200,
            minChunkSize:   1,
            maxChunkSize:   200,
            minPrice:       0,
            deadline:       deadline,
            outputAllocations: outs,
            privateIntent:  priv
        });
    }

    function _sampleIntentOnChain(address verifying, uint256 deadline) internal view returns (DCAIntent memory) {
        // build PrivateIntent with all 0s
        PrivateIntent memory priv = PrivateIntent({
            totalInputAmount: 0,
            exactFrequency:   0,
            numChunks:        0,
            salt:             bytes32(0),
            oracleFeeds:      new bytes32[](0)
        });

        // one or more output allocations
        OutputAllocation[] memory outs = new OutputAllocation[](2);
        outs[0] = OutputAllocation({ recipient: address(0xAAAAA), basisPoints: 9975 });
        outs[1] = OutputAllocation({ recipient: address(0xFFFFF), basisPoints: 25 });

        // outer struct
        return DCAIntent({
            swapper:        signer,
            nonce:          42,
            chainId:        CHAINID,
            hookAddress:    verifying,
            isExactIn:      true,
            inputToken:     address(0x1111),
            outputToken:    address(0x2222),
            cosigner:       address(0x3333),
            minPeriod:      300,
            maxPeriod:      7200,
            minChunkSize:   1,
            maxChunkSize:   200,
            minPrice:       0,
            deadline:       deadline,
            outputAllocations: outs,
            privateIntent:  priv
        });
    }

    function _feedIds() internal pure returns (bytes32[] memory a) {
        a = new bytes32[](2);
        a[0] = keccak256("feed-0");
        a[1] = keccak256("feed-1");
    }

    // --- tests ---

    function test_HashEquivalence_FullVsInnerHash() public view {
        address verifying = address(this);
        bytes32 domainSeparator = _domainSeparator(verifying);
        uint256 deadline = block.timestamp + 1000;

        DCAIntent memory msgFull = _sampleIntent(verifying, deadline);
        DCAIntent memory msgPartial = _sampleIntentOnChain(verifying, deadline);

        // 1) struct hash via full nested struct
        bytes32 structFull = DCALib.hash(msgFull);

        // 2) struct hash via only inner struct hash
        bytes32 innerHash  = DCALib.hashPrivateIntent(msgFull.privateIntent);
        // This struct has the private part 0'd out
        bytes32 structFromInner = DCALib.hashWithInnerHash(msgPartial, innerHash);

        assertEq(structFromInner, structFull, "struct hashes must match");
        // 3) wrap into EIP-712 digest
        bytes32 digest1 = DCALib.digest(domainSeparator, structFull);
        bytes32 digest2 = DCALib.digest(domainSeparator, structFromInner);
        assertEq(digest1, digest2, "digests must match");
    }

    function test_SignAndRecover() public view {
        address verifying = address(this);
        bytes32 domainSeparator = _domainSeparator(verifying);

        uint256 deadline = block.timestamp + 1000;
        DCAIntent memory msgFull = _sampleIntent(verifying, deadline);
        DCAIntent memory msgPartial = _sampleIntentOnChain(verifying, deadline);

        // Hashes
        bytes32 structFull = DCALib.hash(msgFull);
        bytes32 innerHash  = DCALib.hashPrivateIntent(msgFull.privateIntent);
        bytes32 structFromInner = DCALib.hashWithInnerHash(msgPartial, innerHash);
        assertEq(structFromInner, structFull);

        // Digests
        bytes32 digest = DCALib.digest(domainSeparator, structFull);
        bytes32 digest2 = DCALib.digest(domainSeparator, structFromInner);
        assertEq(digest2, digest);

        // Sign and recover
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PK, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        address rec1 = DCALib.recover(digest, sig);
        assertEq(rec1, signer, "recover(full) must equal signer");

        address rec2 = DCALib.recover(digest2, sig);
        assertEq(rec2, signer, "recover(from inner hash) must equal signer");
    }

    function test_Negative_WrongInnerHashBreaksVerification() public view {
        address verifying = address(this);
        bytes32 domainSeparator = _domainSeparator(verifying);

        uint256 deadline = block.timestamp + 1000;
        DCAIntent memory msgFull = _sampleIntent(verifying, deadline);

        // Sign correct digest
        bytes32 structFull = DCALib.hash(msgFull);
        bytes32 digest = DCALib.digest(domainSeparator, structFull);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PK, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        // Tamper only the inner hash
        PrivateIntent memory tampered = msgFull.privateIntent;
        tampered.numChunks = tampered.numChunks + 1;
        bytes32 wrongInner = DCALib.hashPrivateIntent(tampered);

        // Rebuild digest using same outer fields but wrong inner hash
        bytes32 structWrong = DCALib.hashWithInnerHash(msgFull, wrongInner);
        bytes32 digestWrong = DCALib.digest(domainSeparator, structWrong);
        assertTrue(digestWrong != digest, "tampered digest should differ");

        address rec = DCALib.recover(digestWrong, sig);
        assertTrue(rec != signer, "recover should not match signer on wrong digest");
    }

    function test_Negative_WrongOuterField_EvenWithCorrectInnerHash() public view {
        address verifying = address(this);
        bytes32 domainSeparator = _domainSeparator(verifying);

        uint256 deadline = block.timestamp + 1000;

        // 1) Build the original full message and sign its digest
        DCAIntent memory msgFull = _sampleIntent(verifying, deadline);
        bytes32 structFull = DCALib.hash(msgFull);
        bytes32 digest = DCALib.digest(domainSeparator, structFull);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PK, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        // 2) Compute the CORRECT inner hash from the original inner struct
        bytes32 innerHash = DCALib.hashPrivateIntent(msgFull.privateIntent);

        // 3) Tamper an OUTER field (keep inner hash the same)
        DCAIntent memory tamperedOuter = msgFull;
        tamperedOuter.minChunkSize = tamperedOuter.minChunkSize + 2000; // mutate some outer field

        // 4) Rebuild the outer struct hash using the tampered outer + correct innerHash
        bytes32 structWrong = DCALib.hashWithInnerHash(tamperedOuter, innerHash);
        bytes32 digestWrong = DCALib.digest(domainSeparator, structWrong);

        // 5) The digest must differ and recovery must fail
        assertTrue(digestWrong != digest, "tampered outer digest should differ");
        address rec = DCALib.recover(digestWrong, sig);
        assertTrue(rec != signer, "recover should not match signer on tampered outer digest");
    }

}
