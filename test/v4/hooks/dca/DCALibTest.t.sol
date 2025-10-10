// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {DCALib} from "src/v4/hooks/dca/DCALib.sol";
import {
    DCAIntent, PrivateIntent, OutputAllocation, DCAOrderCosignerData, FeedInfo
} from "src/v4/hooks/dca/DCAStructs.sol";

contract DCALibTest is Test {
    // deterministic test key
    uint256 private constant PK = 0xAAAAA;
    address private signer;

    string constant NAME = "DCAHook";
    string constant VERSION = "1";
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
            totalAmount: 1000,
            exactFrequency: 3600, // 1h
            numChunks: 10,
            salt: keccak256("test-salt"),
            oracleFeeds: _feedIds()
        });

        // one or more output allocations
        OutputAllocation[] memory outs = new OutputAllocation[](2);
        outs[0] = OutputAllocation({recipient: address(0xAAAAA), basisPoints: 9975});
        outs[1] = OutputAllocation({recipient: address(0xFFFFF), basisPoints: 25});

        // outer struct
        return DCAIntent({
            swapper: signer,
            nonce: 42,
            chainId: CHAINID,
            hookAddress: verifying,
            isExactIn: true,
            inputToken: address(0x1111),
            outputToken: address(0x2222),
            cosigner: address(0x3333),
            minPeriod: 300,
            maxPeriod: 7200,
            minChunkSize: 1,
            maxChunkSize: 200,
            minPrice: 0,
            deadline: deadline,
            outputAllocations: outs,
            privateIntent: priv
        });
    }

    function _sampleIntentOnChain(address verifying, uint256 deadline) internal view returns (DCAIntent memory) {
        // build PrivateIntent with all 0s
        PrivateIntent memory priv = PrivateIntent({
            totalAmount: 0,
            exactFrequency: 0,
            numChunks: 0,
            salt: bytes32(0),
            oracleFeeds: new FeedInfo[](0)
        });

        // one or more output allocations
        OutputAllocation[] memory outs = new OutputAllocation[](2);
        outs[0] = OutputAllocation({recipient: address(0xAAAAA), basisPoints: 9975});
        outs[1] = OutputAllocation({recipient: address(0xFFFFF), basisPoints: 25});

        // outer struct
        return DCAIntent({
            swapper: signer,
            nonce: 42,
            chainId: CHAINID,
            hookAddress: verifying,
            isExactIn: true,
            inputToken: address(0x1111),
            outputToken: address(0x2222),
            cosigner: address(0x3333),
            minPeriod: 300,
            maxPeriod: 7200,
            minChunkSize: 1,
            maxChunkSize: 200,
            minPrice: 0,
            deadline: deadline,
            outputAllocations: outs,
            privateIntent: priv
        });
    }

    function _feedIds() internal pure returns (FeedInfo[] memory a) {
        a = new FeedInfo[](2);
        a[0] = FeedInfo({
            feedId: keccak256("feed-0"),
            feed_address: address(0x1111111111111111111111111111111111111111),
            feedType: "price"
        });
        a[1] = FeedInfo({
            feedId: keccak256("feed-1"),
            feed_address: address(0x2222222222222222222222222222222222222222),
            feedType: "oracle"
        });
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
        bytes32 innerHash = DCALib.hashPrivateIntent(msgFull.privateIntent);
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
        bytes32 innerHash = DCALib.hashPrivateIntent(msgFull.privateIntent);
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

    // --- Cosigner Data Tests ---

    function _sampleCosignerData() internal view returns (DCAOrderCosignerData memory) {
        return DCAOrderCosignerData({
            swapper: signer,
            nonce: 42,
            execAmount: 100 ether,
            limitAmount: 95 ether,
            orderNonce: 5
        });
    }

    function test_CosignerData_HashAndRecover() public view {
        address verifying = address(this);
        bytes32 domainSeparator = _domainSeparator(verifying);

        DCAOrderCosignerData memory cosignerData = _sampleCosignerData();

        // Hash the cosigner data
        bytes32 structHash = DCALib.hashCosignerData(cosignerData);
        bytes32 digest = DCALib.digest(domainSeparator, structHash);

        // Sign with cosigner private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PK, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        // Recover and verify
        address recovered = DCALib.recover(digest, sig);
        assertEq(recovered, signer, "Recovered cosigner must match");
    }

    function test_CosignerData_DifferentFieldsProduceDifferentHashes() public view {
        DCAOrderCosignerData memory data1 = _sampleCosignerData();
        DCAOrderCosignerData memory data2 = _sampleCosignerData();

        bytes32 hash1 = DCALib.hashCosignerData(data1);
        bytes32 hashOriginal = DCALib.hashCosignerData(data2);
        assertEq(hash1, hashOriginal, "Same data should produce same hash");

        // Test each field produces different hash
        data2.swapper = address(0xBEEF);
        bytes32 hash2 = DCALib.hashCosignerData(data2);
        assertTrue(hash2 != hash1, "Different swapper should produce different hash");

        data2 = _sampleCosignerData();
        data2.nonce = 43;
        hash2 = DCALib.hashCosignerData(data2);
        assertTrue(hash2 != hash1, "Different nonce should produce different hash");

        data2 = _sampleCosignerData();
        data2.execAmount = 101 ether;
        hash2 = DCALib.hashCosignerData(data2);
        assertTrue(hash2 != hash1, "Different execAmount should produce different hash");

        data2 = _sampleCosignerData();
        data2.limitAmount = 96 ether;
        hash2 = DCALib.hashCosignerData(data2);
        assertTrue(hash2 != hash1, "Different limitAmount should produce different hash");

        data2 = _sampleCosignerData();
        data2.orderNonce = 6;
        hash2 = DCALib.hashCosignerData(data2);
        assertTrue(hash2 != hash1, "Different orderNonce should produce different hash");
    }

    function test_CosignerData_WrongSignatureFails() public view {
        address verifying = address(this);
        bytes32 domainSeparator = _domainSeparator(verifying);

        DCAOrderCosignerData memory cosignerData = _sampleCosignerData();

        // Hash the correct data
        bytes32 structHash = DCALib.hashCosignerData(cosignerData);
        bytes32 digest = DCALib.digest(domainSeparator, structHash);

        // Sign with cosigner private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PK, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        // Tamper with the data
        cosignerData.execAmount = 200 ether;
        bytes32 tamperedHash = DCALib.hashCosignerData(cosignerData);
        bytes32 tamperedDigest = DCALib.digest(domainSeparator, tamperedHash);

        // Recovery with tampered digest should not match
        address recovered = DCALib.recover(tamperedDigest, sig);
        assertTrue(recovered != signer, "Tampered data should not verify");
    }

    function test_CosignerData_CrossChainReplay() public view {
        DCAOrderCosignerData memory cosignerData = _sampleCosignerData();

        // Create domain separators for different chains/contracts
        address verifying1 = address(0x1111);
        address verifying2 = address(0x2222);

        bytes32 domain1 = _domainSeparator(verifying1);
        bytes32 domain2 = _domainSeparator(verifying2);

        assertTrue(domain1 != domain2, "Different verifying contracts should have different domains");

        // Same struct hash
        bytes32 structHash = DCALib.hashCosignerData(cosignerData);

        // Different digests due to different domains
        bytes32 digest1 = DCALib.digest(domain1, structHash);
        bytes32 digest2 = DCALib.digest(domain2, structHash);

        assertTrue(digest1 != digest2, "Same data on different domains should produce different digests");

        // Sign for domain1
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PK, digest1);
        bytes memory sig = abi.encodePacked(r, s, v);

        // Verify signature is valid for domain1
        address recovered1 = DCALib.recover(digest1, sig);
        assertEq(recovered1, signer, "Signature should be valid for domain1");

        // Verify signature is invalid for domain2 (replay protection)
        address recovered2 = DCALib.recover(digest2, sig);
        assertTrue(recovered2 != signer, "Signature should be invalid for domain2");
    }

    function testFuzz_CosignerData_AllFields(
        address swapper,
        uint96 nonce,
        uint160 execAmount,
        uint160 limitAmount,
        uint96 orderNonce
    ) public view {
        address verifying = address(this);
        bytes32 domainSeparator = _domainSeparator(verifying);

        DCAOrderCosignerData memory cosignerData = DCAOrderCosignerData({
            swapper: swapper,
            nonce: nonce,
            execAmount: execAmount,
            orderNonce: orderNonce,
            limitAmount: limitAmount
        });

        // Hash should be deterministic
        bytes32 hash1 = DCALib.hashCosignerData(cosignerData);
        bytes32 hash2 = DCALib.hashCosignerData(cosignerData);
        assertEq(hash1, hash2, "Hash should be deterministic");

        // Create digest and sign
        bytes32 digest = DCALib.digest(domainSeparator, hash1);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PK, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        // Recovery should work
        address recovered = DCALib.recover(digest, sig);
        assertEq(recovered, signer, "Recovery should work for any valid data");
    }
}
