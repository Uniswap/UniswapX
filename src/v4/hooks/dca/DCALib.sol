// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {DCAIntent, PrivateIntent, OutputAllocation, DCAOrderCosignerData, FeedInfo} from "./DCAStructs.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

/// @notice helpers for handling DCA intent specs
library DCALib {
    // ----- EIP-712 Domain -----
    bytes32 constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    // ----- Type strings -----
    bytes constant FEED_INFO_TYPE = "FeedInfo(bytes32 feedId,address feed_address,string feedType)";
    bytes32 constant FEED_INFO_TYPEHASH = keccak256(FEED_INFO_TYPE);

    bytes constant PRIVATE_INTENT_TYPE = "PrivateIntent(uint256 totalAmount,uint256 exactFrequency,uint256 numChunks,bytes32 salt,FeedInfo[] oracleFeeds)"
        "FeedInfo(bytes32 feedId,address feed_address,string feedType)";
    bytes32 constant PRIVATE_INTENT_TYPEHASH = keccak256(PRIVATE_INTENT_TYPE);

    bytes constant OUTPUT_ALLOCATION_TYPE = "OutputAllocation(address recipient,uint16 basisPoints)";
    bytes32 constant OUTPUT_ALLOCATION_TYPEHASH = keccak256(OUTPUT_ALLOCATION_TYPE);

    bytes constant DCA_INTENT_TYPE = "DCAIntent(address swapper,uint256 nonce,uint256 chainId,address hookAddress,bool isExactIn,address inputToken,address outputToken,address cosigner,uint256 minPeriod,uint256 maxPeriod,uint256 minChunkSize,uint256 maxChunkSize,uint256 minPrice,uint256 deadline,OutputAllocation[] outputAllocations,PrivateIntent privateIntent)"
        "FeedInfo(bytes32 feedId,address feed_address,string feedType)"
        "OutputAllocation(address recipient,uint16 basisPoints)"
        "PrivateIntent(uint256 totalAmount,uint256 exactFrequency,uint256 numChunks,bytes32 salt,FeedInfo[] oracleFeeds)";
    bytes32 constant DCA_INTENT_TYPEHASH = keccak256(DCA_INTENT_TYPE);

    bytes constant DCA_COSIGNER_DATA_TYPE =
        "DCAOrderCosignerData(address swapper,uint96 nonce,uint160 execAmount,uint96 orderNonce,uint160 limitAmount)";
    bytes32 constant DCA_COSIGNER_DATA_TYPEHASH = keccak256(DCA_COSIGNER_DATA_TYPE);

    // ----- Hash helpers -----

    function _hashFeedInfoArray(FeedInfo[] memory feeds) private pure returns (bytes32) {
        uint256 len = feeds.length;
        bytes32[] memory feedHashes = new bytes32[](len);
        for (uint256 i = 0; i < len; i++) {
            feedHashes[i] = keccak256(
                abi.encode(
                    FEED_INFO_TYPEHASH, feeds[i].feedId, feeds[i].feed_address, keccak256(bytes(feeds[i].feedType))
                )
            );
        }
        return keccak256(abi.encodePacked(feedHashes));
    }

    function _hashOutputAllocations(OutputAllocation[] memory a) private pure returns (bytes32) {
        uint256 len = a.length;
        bytes32[] memory elHashes = new bytes32[](len);
        for (uint256 i = 0; i < len; i++) {
            elHashes[i] = keccak256(abi.encode(OUTPUT_ALLOCATION_TYPEHASH, a[i].recipient, a[i].basisPoints));
        }
        return keccak256(abi.encodePacked(elHashes));
    }

    function hashPrivateIntent(PrivateIntent memory p) internal pure returns (bytes32) {
        bytes32 oracleFeedsHash = _hashFeedInfoArray(p.oracleFeeds);
        return keccak256(
            abi.encode(PRIVATE_INTENT_TYPEHASH, p.totalAmount, p.exactFrequency, p.numChunks, p.salt, oracleFeedsHash)
        );
    }

    function hash(DCAIntent memory intent) internal pure returns (bytes32) {
        bytes32 outputAllocHash = _hashOutputAllocations(intent.outputAllocations);
        bytes32 privateHash = hashPrivateIntent(intent.privateIntent);

        // Use inline assembly to avoid stack-too-deep while maintaining EIP-712 compliance
        // We encode: keccak256(abi.encode(TYPEHASH, swapper, nonce, chainId, hookAddress,
        //                                  isExactIn, inputToken, outputToken, cosigner,
        //                                  minPeriod, maxPeriod, minChunkSize, maxChunkSize,
        //                                  minPrice, deadline, outputAllocHash, privateHash))
        // Total: 17 fields * 32 bytes = 544 bytes (0x220)
        bytes32 typeHash = DCA_INTENT_TYPEHASH;
        bytes32 structHash;
        assembly ("memory-safe") {
            let ptr := mload(0x40) // Get free memory pointer

            // Store all fields in memory
            mstore(ptr, typeHash) // offset 0x00
            mstore(add(ptr, 0x20), mload(intent)) // swapper (offset 0x00 in struct)
            mstore(add(ptr, 0x40), mload(add(intent, 0x20))) // nonce
            mstore(add(ptr, 0x60), mload(add(intent, 0x40))) // chainId
            mstore(add(ptr, 0x80), mload(add(intent, 0x60))) // hookAddress
            mstore(add(ptr, 0xa0), mload(add(intent, 0x80))) // isExactIn
            mstore(add(ptr, 0xc0), mload(add(intent, 0xa0))) // inputToken
            mstore(add(ptr, 0xe0), mload(add(intent, 0xc0))) // outputToken
            mstore(add(ptr, 0x100), mload(add(intent, 0xe0))) // cosigner
            mstore(add(ptr, 0x120), mload(add(intent, 0x100))) // minPeriod
            mstore(add(ptr, 0x140), mload(add(intent, 0x120))) // maxPeriod
            mstore(add(ptr, 0x160), mload(add(intent, 0x140))) // minChunkSize
            mstore(add(ptr, 0x180), mload(add(intent, 0x160))) // maxChunkSize
            mstore(add(ptr, 0x1a0), mload(add(intent, 0x180))) // minPrice
            mstore(add(ptr, 0x1c0), mload(add(intent, 0x1a0))) // deadline
            mstore(add(ptr, 0x1e0), outputAllocHash) // outputAllocations hash
            mstore(add(ptr, 0x200), privateHash) // privateIntent hash

            // Hash the entire 544 bytes (17 * 32)
            structHash := keccak256(ptr, 0x220)
            mstore(0x40, add(ptr, 0x220)) // Update free memory pointer
        }

        return structHash;
    }

    function hashWithInnerHash(DCAIntent memory intent, bytes32 privateIntentHash) internal pure returns (bytes32) {
        bytes32 outputAllocHash = _hashOutputAllocations(intent.outputAllocations);

        // Use inline assembly to avoid stack-too-deep while maintaining EIP-712 compliance
        // Same as hash() but uses the precomputed privateIntentHash instead of computing it
        bytes32 typeHash = DCA_INTENT_TYPEHASH;
        bytes32 structHash;
        assembly ("memory-safe") {
            let ptr := mload(0x40) // Get free memory pointer

            // Store all fields in memory
            mstore(ptr, typeHash) // offset 0x00
            mstore(add(ptr, 0x20), mload(intent)) // swapper
            mstore(add(ptr, 0x40), mload(add(intent, 0x20))) // nonce
            mstore(add(ptr, 0x60), mload(add(intent, 0x40))) // chainId
            mstore(add(ptr, 0x80), mload(add(intent, 0x60))) // hookAddress
            mstore(add(ptr, 0xa0), mload(add(intent, 0x80))) // isExactIn
            mstore(add(ptr, 0xc0), mload(add(intent, 0xa0))) // inputToken
            mstore(add(ptr, 0xe0), mload(add(intent, 0xc0))) // outputToken
            mstore(add(ptr, 0x100), mload(add(intent, 0xe0))) // cosigner
            mstore(add(ptr, 0x120), mload(add(intent, 0x100))) // minPeriod
            mstore(add(ptr, 0x140), mload(add(intent, 0x120))) // maxPeriod
            mstore(add(ptr, 0x160), mload(add(intent, 0x140))) // minChunkSize
            mstore(add(ptr, 0x180), mload(add(intent, 0x160))) // maxChunkSize
            mstore(add(ptr, 0x1a0), mload(add(intent, 0x180))) // minPrice
            mstore(add(ptr, 0x1c0), mload(add(intent, 0x1a0))) // deadline
            mstore(add(ptr, 0x1e0), outputAllocHash) // outputAllocations hash
            mstore(add(ptr, 0x200), privateIntentHash) // privateIntent hash (precomputed)

            // Hash the entire 544 bytes (17 * 32)
            structHash := keccak256(ptr, 0x220)
            mstore(0x40, add(ptr, 0x220)) // Update free memory pointer
        }

        return structHash;
    }

    function hashCosignerData(DCAOrderCosignerData memory cosignerData) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                DCA_COSIGNER_DATA_TYPEHASH,
                cosignerData.swapper,
                cosignerData.nonce,
                cosignerData.execAmount,
                cosignerData.orderNonce,
                cosignerData.limitAmount
            )
        );
    }

    function digest(bytes32 domainSeparator, bytes32 structHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    // Validate signature (supports both EOA and EIP-1271 smart contract wallets)
    function isValidSignature(address signer, bytes32 digest_, bytes memory signature) internal view returns (bool) {
        return SignatureChecker.isValidSignatureNow(signer, digest_, signature);
    }

    /// @notice Computes the domain separator using the current chainId and contract address
    /// @param verifyingContract The address of the contract that will verify signatures
    /// @return The EIP-712 domain separator
    function computeDomainSeparator(address verifyingContract) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes("DCAHook")),
                keccak256(bytes("1")),
                block.chainid,
                verifyingContract
            )
        );
    }
}
