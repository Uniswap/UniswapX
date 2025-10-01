// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {DCAIntent, PrivateIntent, OutputAllocation, DCAOrderCosignerData} from "./DCAStructs.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

library DCALib {
    // ----- EIP-712 Domain -----
    bytes32 constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    // ----- Type strings -----
    bytes constant PRIVATE_INTENT_TYPE =
        "PrivateIntent(uint256 totalAmount,uint256 exactFrequency,uint256 numChunks,bytes32 salt,bytes32[] oracleFeeds)";
    bytes32 constant PRIVATE_INTENT_TYPEHASH = keccak256(PRIVATE_INTENT_TYPE);

    bytes constant OUTPUT_ALLOCATION_TYPE = "OutputAllocation(address recipient,uint256 basisPoints)";
    bytes32 constant OUTPUT_ALLOCATION_TYPEHASH = keccak256(OUTPUT_ALLOCATION_TYPE);

    bytes constant DCA_INTENT_TYPE =
        "DCAIntent(address swapper,uint256 nonce,uint256 chainId,address hookAddress,bool isExactIn,address inputToken,address outputToken,address cosigner,uint256 minPeriod,uint256 maxPeriod,uint256 minChunkSize,uint256 maxChunkSize,uint256 minPrice,uint256 deadline,OutputAllocation[] outputAllocations,PrivateIntent privateIntent)"
        "OutputAllocation(address recipient,uint256 basisPoints)"
        "PrivateIntent(uint256 totalAmount,uint256 exactFrequency,uint256 numChunks,bytes32 salt,bytes32[] oracleFeeds)";
    bytes32 constant DCA_INTENT_TYPEHASH = keccak256(DCA_INTENT_TYPE);

    bytes constant DCA_COSIGNER_DATA_TYPE =
        "DCAOrderCosignerData(address swapper,uint256 nonce,uint256 execAmount,uint256 limitAmount,uint96 orderNonce)";
    bytes32 constant DCA_COSIGNER_DATA_TYPEHASH = keccak256(DCA_COSIGNER_DATA_TYPE);

    // ----- Hash helpers -----

    function _hashBytes32Array(bytes32[] memory arr) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(arr));
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
        bytes32 oracleFeedsHash = _hashBytes32Array(p.oracleFeeds);
        return keccak256(
            abi.encode(
                PRIVATE_INTENT_TYPEHASH, p.totalAmount, p.exactFrequency, p.numChunks, p.salt, oracleFeedsHash
            )
        );
    }

    function hash(DCAIntent memory intent) internal pure returns (bytes32) {
        bytes32 outputAllocHash = _hashOutputAllocations(intent.outputAllocations);
        bytes32 privateHash = hashPrivateIntent(intent.privateIntent);

        // Doing in 2 pieces to avoid stack too deep
        bytes32 paramsHash1 = keccak256(
            abi.encode(
                intent.swapper,
                intent.nonce,
                intent.chainId,
                intent.hookAddress,
                intent.isExactIn,
                intent.inputToken,
                intent.outputToken
            )
        );

        bytes32 paramsHash2 = keccak256(
            abi.encode(
                intent.cosigner,
                intent.minPeriod,
                intent.maxPeriod,
                intent.minChunkSize,
                intent.maxChunkSize,
                intent.minPrice,
                intent.deadline
            )
        );

        return keccak256(abi.encode(DCA_INTENT_TYPEHASH, paramsHash1, paramsHash2, outputAllocHash, privateHash));
    }

    function hashWithInnerHash(DCAIntent memory intent, bytes32 privateIntentHash) internal pure returns (bytes32) {
        bytes32 outputAllocHash = _hashOutputAllocations(intent.outputAllocations);

        // Doing in 2 pieces to avoid stack too deep
        bytes32 paramsHash1 = keccak256(
            abi.encode(
                intent.swapper,
                intent.nonce,
                intent.chainId,
                intent.hookAddress,
                intent.isExactIn,
                intent.inputToken,
                intent.outputToken
            )
        );

        bytes32 paramsHash2 = keccak256(
            abi.encode(
                intent.cosigner,
                intent.minPeriod,
                intent.maxPeriod,
                intent.minChunkSize,
                intent.maxChunkSize,
                intent.minPrice,
                intent.deadline
            )
        );

        return keccak256(abi.encode(DCA_INTENT_TYPEHASH, paramsHash1, paramsHash2, outputAllocHash, privateIntentHash));
    }

    function hashCosignerData(DCAOrderCosignerData memory cosignerData) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                DCA_COSIGNER_DATA_TYPEHASH,
                cosignerData.swapper,
                cosignerData.nonce,
                cosignerData.execAmount,
                cosignerData.limitAmount,
                cosignerData.orderNonce
            )
        );
    }

    function digest(bytes32 domainSeparator, bytes32 structHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    // Recover signer
    function recover(bytes32 digest_, bytes memory signature) internal pure returns (address) {
        return ECDSA.recover(digest_, signature);
    }

    // Compute domain separator
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
