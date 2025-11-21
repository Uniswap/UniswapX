// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {DCALib} from "src/v4/hooks/dca/DCALib.sol";
import {DCAIntent, PrivateIntent, OutputAllocation, FeedInfo} from "src/v4/hooks/dca/DCAStructs.sol";
import {FFISignDCAIntent} from "./FFISignDCAIntent.sol";

/**
 * @title DCALib EIP-712 Compliance Test
 * @notice This test verifies that our inline assembly implementation of DCAIntent hashing
 *         produces the exact same results as standard JavaScript EIP-712 libraries (viem).
 *         This is critical to ensure users can sign intents with standard wallets.
 */
contract DCALibEIP712ComplianceTest is Test, FFISignDCAIntent {
    address constant HOOK_ADDRESS = address(0x1111);
    uint256 constant PRIVATE_KEY = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
    address immutable SIGNER;

    constructor() {
        SIGNER = vm.addr(PRIVATE_KEY);
    }

    function setUp() public {
        // Label addresses for better trace output
        vm.label(HOOK_ADDRESS, "DCAHook");
        vm.label(SIGNER, "Signer");
    }

    /**
     * @notice Test that our Solidity hash matches the hash computed by standard JS library
     * @dev This is the core test - if this passes, our assembly implementation is EIP-712 compliant
     */
    function test_HashMatchesJavaScriptLibrary() public {
        DCAIntent memory intent = _createSimpleIntent();

        // Compute hash using our Solidity implementation (with inline assembly)
        bytes32 solidityHash = DCALib.hash(intent);

        // Compute hash using standard JavaScript EIP-712 library (viem)
        SignResult memory jsResult = ffi_signDCAIntent(PRIVATE_KEY, HOOK_ADDRESS, block.chainid, intent);

        // The hashes MUST match exactly
        assertEq(solidityHash, jsResult.structHash, "Solidity hash does not match JavaScript library hash!");

        console2.log("SUCCESS: Solidity hash matches JavaScript EIP-712 library");
        console2.log("Hash:", vm.toString(solidityHash));
    }

    /**
     * @notice Test signature recovery - verifies complete EIP-712 flow
     * @dev If we can recover the correct signer, our implementation is fully EIP-712 compliant
     */
    function test_SignatureRecoveryFromJavaScript() public {
        DCAIntent memory intent = _createSimpleIntent();

        // Get signature from JavaScript using standard signTypedData
        SignResult memory jsResult = ffi_signDCAIntent(PRIVATE_KEY, HOOK_ADDRESS, block.chainid, intent);

        // Compute the full EIP-712 digest
        bytes32 domainSeparator = DCALib.computeDomainSeparator(HOOK_ADDRESS);
        bytes32 structHash = DCALib.hash(intent);
        bytes32 digest = DCALib.digest(domainSeparator, structHash);

        // Recover the signer from the JavaScript signature
        address recovered = DCALib.recover(digest, jsResult.signature);

        // Should recover the correct signer address
        assertEq(recovered, SIGNER, "Failed to recover correct signer from JavaScript signature!");

        console2.log("SUCCESS: Recovered correct signer from standard wallet signature");
        console2.log("Expected:", SIGNER);
        console2.log("Recovered:", recovered);
    }

    /**
     * @notice Test with complex intent (multiple allocations, oracle feeds)
     */
    function test_ComplexIntentMatchesJavaScript() public {
        DCAIntent memory intent = _createComplexIntent();

        bytes32 solidityHash = DCALib.hash(intent);
        SignResult memory jsResult = ffi_signDCAIntent(PRIVATE_KEY, HOOK_ADDRESS, block.chainid, intent);

        assertEq(solidityHash, jsResult.structHash, "Complex intent hash mismatch!");

        console2.log("SUCCESS: Complex intent hash matches JavaScript library");
    }

    /**
     * @notice Test hashWithInnerHash variant
     */
    function test_HashWithInnerHashMatchesJavaScript() public {
        DCAIntent memory intent = _createSimpleIntent();

        // Pre-compute the private intent hash
        bytes32 privateIntentHash = DCALib.hashPrivateIntent(intent.privateIntent);

        // Use the variant that accepts pre-computed hash
        bytes32 solidityHash = DCALib.hashWithInnerHash(intent, privateIntentHash);

        // Should match the JavaScript library
        SignResult memory jsResult = ffi_signDCAIntent(PRIVATE_KEY, HOOK_ADDRESS, block.chainid, intent);

        assertEq(solidityHash, jsResult.structHash, "hashWithInnerHash does not match JavaScript!");

        console2.log("SUCCESS: hashWithInnerHash variant matches JavaScript library");
    }

    /**
     * @notice Fuzz test - verify compliance across random inputs
     */
    function testFuzz_HashMatchesJavaScript(
        address swapper,
        uint256 nonce,
        uint256 minPeriod,
        uint256 maxPeriod,
        uint256 minChunkSize,
        uint256 maxChunkSize,
        uint256 minPrice,
        uint256 deadline
    ) public {
        // Bound inputs to reasonable ranges
        vm.assume(maxPeriod >= minPeriod && minPeriod > 0);
        vm.assume(maxChunkSize >= minChunkSize && minChunkSize > 0);
        vm.assume(deadline > block.timestamp);
        vm.assume(swapper != address(0));

        DCAIntent memory intent = DCAIntent({
            swapper: swapper,
            nonce: nonce,
            chainId: block.chainid,
            hookAddress: HOOK_ADDRESS,
            isExactIn: true,
            inputToken: address(0x1),
            outputToken: address(0x2),
            cosigner: address(0x3),
            minPeriod: minPeriod,
            maxPeriod: maxPeriod,
            minChunkSize: minChunkSize,
            maxChunkSize: maxChunkSize,
            minPrice: minPrice,
            deadline: deadline,
            outputAllocations: _createSimpleAllocations(),
            privateIntent: _createSimplePrivateIntent()
        });

        bytes32 solidityHash = DCALib.hash(intent);
        SignResult memory jsResult = ffi_signDCAIntent(PRIVATE_KEY, HOOK_ADDRESS, block.chainid, intent);

        assertEq(solidityHash, jsResult.structHash, "Fuzz test: hash mismatch!");
    }

    // Helper functions to create test data

    function _createSimpleIntent() internal view returns (DCAIntent memory) {
        return DCAIntent({
            swapper: address(0xABCD),
            nonce: 1,
            chainId: block.chainid,
            hookAddress: HOOK_ADDRESS,
            isExactIn: true,
            inputToken: address(0x1111111111111111111111111111111111111111),
            outputToken: address(0x2222222222222222222222222222222222222222),
            cosigner: address(0x3333333333333333333333333333333333333333),
            minPeriod: 3600,
            maxPeriod: 7200,
            minChunkSize: 1e18,
            maxChunkSize: 10e18,
            minPrice: 1e18,
            deadline: block.timestamp + 30 days,
            outputAllocations: _createSimpleAllocations(),
            privateIntent: _createSimplePrivateIntent()
        });
    }

    function _createComplexIntent() internal view returns (DCAIntent memory) {
        OutputAllocation[] memory allocations = new OutputAllocation[](3);
        allocations[0] = OutputAllocation({recipient: address(0xAAAA), basisPoints: 5000});
        allocations[1] = OutputAllocation({recipient: address(0xBBBB), basisPoints: 3000});
        allocations[2] = OutputAllocation({recipient: address(0xCCCC), basisPoints: 2000});

        FeedInfo[] memory feeds = new FeedInfo[](2);
        feeds[0] = FeedInfo({feedId: bytes32(uint256(1)), feed_address: address(0xFEED1), feedType: "asdf"});
        feeds[1] = FeedInfo({feedId: bytes32(uint256(2)), feed_address: address(0xFEED2), feedType: "qwer"});

        PrivateIntent memory privateIntent = PrivateIntent({
            totalAmount: 100e18, exactFrequency: 3600, numChunks: 10, salt: keccak256("test-salt"), oracleFeeds: feeds
        });

        return DCAIntent({
            swapper: address(0xABCD),
            nonce: 42,
            chainId: block.chainid,
            hookAddress: HOOK_ADDRESS,
            isExactIn: false,
            inputToken: address(0x1111111111111111111111111111111111111111),
            outputToken: address(0x2222222222222222222222222222222222222222),
            cosigner: address(0x3333333333333333333333333333333333333333),
            minPeriod: 1800,
            maxPeriod: 14400,
            minChunkSize: 5e18,
            maxChunkSize: 50e18,
            minPrice: 95e16, // 0.95e18
            deadline: block.timestamp + 60 days,
            outputAllocations: allocations,
            privateIntent: privateIntent
        });
    }

    function _createSimpleAllocations() internal pure returns (OutputAllocation[] memory) {
        OutputAllocation[] memory allocations = new OutputAllocation[](1);
        allocations[0] = OutputAllocation({recipient: address(0x9999), basisPoints: 10000});
        return allocations;
    }

    function _createSimplePrivateIntent() internal pure returns (PrivateIntent memory) {
        FeedInfo[] memory feeds = new FeedInfo[](1);
        feeds[0] = FeedInfo({feedId: bytes32(uint256(123)), feed_address: address(0xFEED), feedType: "asdf"});

        return PrivateIntent({
            totalAmount: 100e18, exactFrequency: 3600, numChunks: 10, salt: bytes32(uint256(0x42)), oracleFeeds: feeds
        });
    }
}
