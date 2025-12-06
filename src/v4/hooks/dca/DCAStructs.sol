// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";

struct FeedTemplate {
    string name;
    string expression;
    string[] parameters;
    string[] secrets;
    uint256 retryCount;
}

struct FeedInfo {
    FeedTemplate feedTemplate;
    address feedAddress;
    string feedType;
}

struct DCAIntent {
    address swapper;
    uint256 nonce;
    uint256 chainId;
    address hookAddress; // DCA contract's address
    bool isExactIn; // EXACT_IN or EXACT_OUT
    address inputToken; // Token to sell
    address outputToken; // Token to buy
    address cosigner; // TEE address that authorizes executions
    uint256 minPeriod; // Minimum seconds between chunks
    uint256 maxPeriod; // Maximum seconds between chunks
    uint256 minChunkSize; // Min input or min output per chunk
    uint256 maxChunkSize; // Max input or max output per chunk
    uint256 minPrice; // Minimum price (output/input * 1e18)
    uint256 deadline; // Intent expiration timestamp
    OutputAllocation[] outputAllocations; // Distribution of output tokens
    PrivateIntent privateIntent; // Private execution parameters - included in EIP-712 signature but zeroed on-chain, only hash revealed
}

struct PrivateIntent {
    uint256 totalAmount; // Total amount on the exact side (input for EXACT_IN, output for EXACT_OUT)
    uint256 exactFrequency;
    uint256 numChunks;
    bytes32 salt;
    FeedInfo[] oracleFeeds; // Array of possible oracle feeds
}

struct OutputAllocation {
    address recipient; // 20 bytes
    uint16 basisPoints; // 2 bytes - Out of 10000 (100% = 10000), packed in same slot
}

struct DCAOrderCosignerData {
    address swapper; // 20 bytes, slot 1
    uint96 nonce; // 12 bytes
    uint160 execAmount; // 20 bytes, slot 2
    uint96 orderNonce; // 12 bytes Unique execution chunk identifier
    uint160 limitAmount; // 20 bytes, slot 3 (12 bytes padding)
    // uint160 matches Permit2's transferFrom amount limit
}

struct DCAExecutionState {
    uint128 executedChunks; // 16 bytes slot 1 (perfectly packed)
    uint120 lastExecutionTime; // 15 bytes
    bool cancelled; // 1 byte
    uint256 totalInputExecuted; // 32 bytes   slot 2 - Cumulative input amount
    uint256 totalOutput; // 32 bytes   slot 3 - Cumulative output amount
}

struct PermitData {
    bool hasPermit; // Whether a permit signature is included
    IAllowanceTransfer.PermitSingle permitSingle; // The permit data (if hasPermit is true)
    bytes signature; // The permit signature (if hasPermit is true)
}
