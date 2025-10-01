// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

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
    PrivateIntent privateIntent; // Nested struct (zeroed on-chain)
}

struct PrivateIntent {
    uint256 totalInputAmount;
    uint256 exactFrequency;
    uint256 numChunks;
    bytes32 salt;
    bytes32[] oracleFeeds; // Array of possible oracle feed IDs
}

struct OutputAllocation {
    address recipient;
    uint256 basisPoints; // Out of 10000 (100% = 10000)
}

struct DCAOrderCosignerData {
    address swapper;
    uint256 nonce;
    uint256 execAmount; // Amount being executed (input for EXACT_IN, output for EXACT_OUT)
    uint256 limitAmount; // Limit/bound (min output for EXACT_IN, max input for EXACT_OUT)
    uint96 orderNonce; // Unique execution chunk identifier (uint96)
}

struct DCAExecutionState {
    uint96 nextNonce; // Next valid nonce (packs with cancelled)
    bool cancelled; // Cancellation flag
    uint256 executedChunks; // Number of chunks executed
    uint256 lastExecutionTime; // Last execution timestamp
    uint256 totalInputExecuted; // Cumulative input amount
    uint256 totalOutput; // Cumulative output amount
}
