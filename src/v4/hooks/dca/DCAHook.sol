// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IDCAHook} from "../../interfaces/IDCAHook.sol";
import {IPreExecutionHook} from "../../interfaces/IHook.sol";
import {ResolvedOrder, InputToken, OutputToken} from "../../base/ReactorStructs.sol";
import {DCAIntent, DCAExecutionState, DCAOrderCosignerData, OutputAllocation} from "./DCAStructs.sol";
import {DCALib} from "./DCALib.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {Permit2Lib} from "../../lib/Permit2Lib.sol";
import {IAuctionResolver} from "../../interfaces/IAuctionResolver.sol";
import {Math} from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";

/// @title DCAHook
/// @notice DCA hook implementation for UniswapX that validates and executes DCA intents
/// @dev Implements IPreExecutionHook for flexibility
contract DCAHook is IPreExecutionHook, IDCAHook {
    using Permit2Lib for ResolvedOrder;
    /// @notice Permit2 instance for signature verification and token transfers

    IPermit2 public immutable permit2;

    /// @notice EIP-712 domain separator
    bytes32 public immutable domainSeparator;

    /// @notice Mapping from intentId to execution state
    /// @dev intentId is computed as keccak256(abi.encodePacked(swapper, nonce))
    mapping(bytes32 => DCAExecutionState) internal executionStates;

    constructor(IPermit2 _permit2) {
        permit2 = _permit2;
        domainSeparator = DCALib.computeDomainSeparator(address(this));
    }

    /// @inheritdoc IPreExecutionHook
    function preExecutionHook(address filler, ResolvedOrder calldata resolvedOrder) external override {
        // First validate the DCA intent
        _validateDCAIntent(filler, resolvedOrder);

        // Then transfer input tokens
        _transferInputTokens(resolvedOrder, filler);
    }

    /// @notice Validates DCA intent and prepares for token transfer
    /// @dev Called before token transfer to validate the DCA order
    /// @param resolvedOrder The resolved order to fill
    function _validateDCAIntent(address, ResolvedOrder calldata resolvedOrder) internal {
        // 1) Decode pre-execution data
        (
            DCAIntent memory intent, // PrivateIntent is zeroed on-chain
            bytes memory swapperSignature,
            bytes32 privateIntentHash, // EIP-712 replacement for zeroed PrivateIntent
            DCAOrderCosignerData memory cosignerData,
            bytes memory cosignerSignature
        ) = abi.decode(
            resolvedOrder.info.preExecutionHookData, (DCAIntent, bytes, bytes32, DCAOrderCosignerData, bytes)
        );

        // 2) Compute intentId for state lookups
        bytes32 intentId = keccak256(abi.encodePacked(intent.swapper, intent.nonce));

        // 3) Verify swapper signature (EIP-712) over full intent with privateIntentHash
        _validateSwapperSignature(intent, privateIntentHash, swapperSignature);

        // 4) Static field checks (binding correctness)
        _validateStaticFields(intent, resolvedOrder);

        // 5) Output allocations validation
        _validateAllocations(intent.outputAllocations);

        // 6) Verify cosigner authorization
        _validateCosignerSignature(intent, cosignerData, cosignerSignature);

        // 7) State checks and period gating
        _validateStateAndTiming(intentId, intent, cosignerData);

        // 8) Chunk size checks
        _validateChunkSize(intent, cosignerData, resolvedOrder.input.amount);

        // 9) Price floor check (1e18 scaling)
        _validatePriceFloor(intent, cosignerData);

        // 10) Output validation and allocations
        _validateOutputsAndAllocations(intent, cosignerData, resolvedOrder.outputs);

        // 11) Update execution state
        _updateExecutionState(intentId, resolvedOrder.input.amount, resolvedOrder.outputs);
    }

    function _transferInputTokens(ResolvedOrder calldata order, address to) private {
        // TODO: Implement token transfer logic with AllowanceTransfer
    }

    /// @inheritdoc IDCAHook
    function cancelIntents(uint256[] calldata nonces) external override {
        for (uint256 i = 0; i < nonces.length; i++) {
            _cancelIntent(msg.sender, nonces[i]);
        }
    }

    /// @inheritdoc IDCAHook
    function cancelIntent(uint256 nonce) external override {
        _cancelIntent(msg.sender, nonce);
    }

    function _cancelIntent(address swapper, uint256 nonce) internal {
        bytes32 intentId = keccak256(abi.encodePacked(swapper, nonce));
        if (executionStates[intentId].cancelled) {
            revert IntentAlreadyCancelled(intentId);
        }
        executionStates[intentId].cancelled = true;
        emit IntentCancelled(intentId, swapper);
    }

    /// @notice Validates the swapper's EIP-712 signature over the DCA intent
    /// @dev Verifies the signature using the provided private intent hash to reconstruct the full intent hash
    /// @param intent The DCA intent to validate (with zeroed privateIntent field)
    /// @param privateIntentHash The hash of the private intent data (computed off-chain)
    /// @param swapperSignature The EIP-712 signature from the swapper
    function _validateSwapperSignature(
        DCAIntent memory intent,
        bytes32 privateIntentHash,
        bytes memory swapperSignature
    ) internal view {
        bytes32 fullIntentHash = DCALib.hashWithInnerHash(intent, privateIntentHash);
        bytes32 digest = DCALib.digest(domainSeparator, fullIntentHash);
        address recoveredSigner = DCALib.recover(digest, swapperSignature);
        if (recoveredSigner != intent.swapper) {
            revert InvalidSwapperSignature(recoveredSigner, intent.swapper);
        }
    }

    /// @notice Validates the cosigner's EIP-712 signature and authorization data
    /// @dev Verifies both the signature and that cosigner data matches the intent
    /// @param intent The DCA intent containing expected cosigner and swapper/nonce info
    /// @param cosignerData The cosigner authorization data containing execution parameters
    /// @param cosignerSignature The EIP-712 signature from the cosigner
    function _validateCosignerSignature(
        DCAIntent memory intent,
        DCAOrderCosignerData memory cosignerData,
        bytes memory cosignerSignature
    ) internal view {
        bytes32 cosignerStructHash = DCALib.hashCosignerData(cosignerData);
        bytes32 cosignerDigest = DCALib.digest(domainSeparator, cosignerStructHash);
        address recoveredCosigner = DCALib.recover(cosignerDigest, cosignerSignature);
        if (recoveredCosigner != intent.cosigner) {
            revert InvalidCosignerSignature(recoveredCosigner, intent.cosigner);
        }
        if (cosignerData.swapper != intent.swapper) {
            revert CosignerSwapperMismatch(cosignerData.swapper, intent.swapper);
        }
        if (cosignerData.nonce != intent.nonce) {
            revert CosignerNonceMismatch(cosignerData.nonce, intent.nonce);
        }
    }

    /// @notice Validates that output allocations sum to exactly 100% (10000 basis points)
    /// @dev Reverts if allocations don't sum to 10000 or if array is empty
    /// @dev NOTE: This function intentionally allows:
    ///      - Duplicate recipients (same address multiple times) - checked off-chain
    ///      - Zero address as recipient - validated off-chain for user safety
    ///      These are permitted at the contract level to support advanced use cases
    ///      but should be prevented in the UI/frontend for typical users
    /// @param outputAllocations The array of output allocations to validate
    function _validateAllocations(OutputAllocation[] memory outputAllocations) internal pure {
        uint256 length = outputAllocations.length;
        if (length == 0) {
            revert EmptyAllocations();
        }

        uint256 totalBasisPoints;
        for (uint256 i = 0; i < length;) {
            uint256 basisPoints = outputAllocations[i].basisPoints;
            if (basisPoints == 0) {
                revert ZeroAllocation();
            }

            totalBasisPoints += basisPoints;
            if (totalBasisPoints > 10000) {
                revert AllocationsExceed100Percent();
            }

            unchecked {
                ++i;
            }
        }

        if (totalBasisPoints != 10000) {
            revert AllocationsNot100Percent(totalBasisPoints);
        }
    }

    /// @notice Validates static fields match between intent and order
    /// @dev Ensures the intent is bound to correct hook, chain, swapper, and tokens
    /// @param intent The DCA intent containing expected values
    /// @param resolvedOrder The resolved order to validate against
    function _validateStaticFields(DCAIntent memory intent, ResolvedOrder memory resolvedOrder) internal view {
        if (intent.hookAddress != address(this)) {
            revert WrongHook(intent.hookAddress, address(this));
        }
        if (intent.chainId != block.chainid) {
            revert WrongChain(intent.chainId, block.chainid);
        }
        if (resolvedOrder.info.swapper != intent.swapper) {
            revert SwapperMismatch(resolvedOrder.info.swapper, intent.swapper);
        }
        if (address(resolvedOrder.input.token) != intent.inputToken) {
            revert WrongInputToken(address(resolvedOrder.input.token), intent.inputToken);
        }

        // Verify all outputs use the correct output token
        for (uint256 i = 0; i < resolvedOrder.outputs.length; i++) {
            if (resolvedOrder.outputs[i].token != intent.outputToken) {
                revert WrongOutputToken(resolvedOrder.outputs[i].token, intent.outputToken);
            }
        }
    }

    /// @notice Validates chunk size is within the allowed bounds
    /// @dev Checks that execAmount is within min/max chunk size for the given order type
    /// @param intent The DCA intent containing chunk size constraints
    /// @param cosignerData The cosigner data containing execution amounts
    /// @param inputAmount The actual input amount from the resolved order
    function _validateChunkSize(DCAIntent memory intent, DCAOrderCosignerData memory cosignerData, uint256 inputAmount)
        internal
        pure
    {
        if (intent.isExactIn) {
            if (cosignerData.execAmount < intent.minChunkSize) {
                revert InputBelowMin(cosignerData.execAmount, intent.minChunkSize);
            }
            if (cosignerData.execAmount > intent.maxChunkSize) {
                revert InputAboveMax(cosignerData.execAmount, intent.maxChunkSize);
            }
            // We will transfer order.input.amount; ensure it matches execAmount for EXACT_IN
            if (inputAmount != cosignerData.execAmount) {
                revert InputAmountMismatch(inputAmount, cosignerData.execAmount);
            }
        } else {
            // EXACT_OUT: execAmount is the exact output amount to deliver
            if (cosignerData.execAmount < intent.minChunkSize) {
                revert OutputBelowMin(cosignerData.execAmount, intent.minChunkSize);
            }
            if (cosignerData.execAmount > intent.maxChunkSize) {
                revert OutputAboveMax(cosignerData.execAmount, intent.maxChunkSize);
            }
            if (inputAmount == 0) {
                revert ZeroInput();
            }
            if (inputAmount > cosignerData.limitAmount) {
                revert InputAboveLimit(inputAmount, cosignerData.limitAmount);
            }
        }
    }

    /// @notice Validates execution state and timing constraints
    /// @dev Checks cancellation status, deadline, nonce, and period gating
    /// @param intentId The unique identifier for this DCA intent
    /// @param intent The DCA intent containing timing constraints
    /// @param cosignerData The cosigner data containing the order nonce
    function _validateStateAndTiming(
        bytes32 intentId,
        DCAIntent memory intent,
        DCAOrderCosignerData memory cosignerData
    ) internal view {
        // Load to memory to minimize SLOADs
        DCAExecutionState memory state = executionStates[intentId];

        // State checks
        if (state.cancelled) {
            revert IntentIsCancelled(intentId);
        }
        if (intent.deadline != 0 && block.timestamp > intent.deadline) {
            revert IntentExpired(block.timestamp, intent.deadline);
        }
        if (cosignerData.orderNonce != state.nextNonce) {
            revert WrongChunkNonce(cosignerData.orderNonce, state.nextNonce);
        }

        // Period gating (enforce minPeriod/maxPeriod only after first execution)
        if (state.executedChunks > 0) {
            uint256 elapsed = block.timestamp - state.lastExecutionTime;
            if (elapsed < intent.minPeriod) {
                revert TooSoon(elapsed, intent.minPeriod);
            }
            if (intent.maxPeriod != 0 && elapsed > intent.maxPeriod) {
                revert TooLate(elapsed, intent.maxPeriod);
            }
        }
    }

    /// @notice Validates that the execution price meets the minimum price floor
    /// @dev Calculates price based on order type and ensures it meets the minimum
    /// @param intent The DCA intent containing the minimum price requirement
    /// @param cosignerData The cosigner data containing execution and limit amounts
    function _validatePriceFloor(DCAIntent memory intent, DCAOrderCosignerData memory cosignerData) internal pure {
        uint256 executionPrice;
        if (intent.isExactIn) {
            // limitAmount = min acceptable output; execAmount = exact input
            // Price = output/input * 1e18
            executionPrice = Math.mulDiv(cosignerData.limitAmount, 1e18, cosignerData.execAmount);
        } else {
            // execAmount = exact output; limitAmount = max acceptable input
            // Price = output/input * 1e18
            executionPrice = Math.mulDiv(cosignerData.execAmount, 1e18, cosignerData.limitAmount);
        }
        if (executionPrice < intent.minPrice) {
            revert PriceBelowMin(executionPrice, intent.minPrice);
        }
    }

    /// @notice Validates outputs match expected allocations and amounts
    /// @dev Verifies that outputs are distributed according to the intent's allocations
    /// @param intent The DCA intent containing allocation requirements
    /// @param cosignerData The cosigner data containing limit amounts
    /// @param outputs The actual outputs from the resolved order
    function _validateOutputsAndAllocations(
        DCAIntent memory intent,
        DCAOrderCosignerData memory cosignerData,
        OutputToken[] memory outputs
    ) internal pure {
        // Aggregate outputs per recipient and compute totalOutput
        uint256 totalOutput = 0;
        // Use a temporary in-memory structure to tally by recipient (no memory mapping in Solidity):
        // Approach: loop once to total output; for each allocation, loop outputs to sum matching recipient.
        for (uint256 i = 0; i < outputs.length; i++) {
            // token already checked equals intent.outputToken in _beforeTokenTransfer
            totalOutput += outputs[i].amount;
        }

        for (uint256 i = 0; i < intent.outputAllocations.length; i++) {
            address rcpt = intent.outputAllocations[i].recipient;
            uint256 expected = Math.mulDiv(totalOutput, intent.outputAllocations[i].basisPoints, 10000);
            uint256 actual = 0;
            for (uint256 j = 0; j < outputs.length; j++) {
                if (outputs[j].recipient == rcpt) actual += outputs[j].amount;
            }
            if (intent.isExactIn) {
                // Allow ±1 wei for integer division rounding
                if (!(actual + 1 >= expected && actual <= expected + 1)) {
                    revert AllocationMismatch(rcpt, actual, expected);
                }
            } else {
                if (actual != expected) {
                    revert AllocationMismatch(rcpt, actual, expected);
                }
            }
        }

        if (intent.isExactIn) {
            // total output produced must meet the limit
            if (totalOutput < cosignerData.limitAmount) {
                revert InsufficientOutput(totalOutput, cosignerData.limitAmount);
            }
        } else {
            // exact output must be matched
            if (totalOutput != cosignerData.execAmount) {
                revert WrongTotalOutput(totalOutput, cosignerData.execAmount);
            }
        }
    }

    /// @notice Updates the execution state after successful validation
    /// @dev Updates counters, totals, timestamps and nonce for the DCA intent
    /// @param intentId The unique identifier for this DCA intent
    /// @param inputAmount The amount of input tokens being executed
    /// @param outputs The output tokens being distributed
    function _updateExecutionState(bytes32 intentId, uint256 inputAmount, OutputToken[] memory outputs) internal {
        // Use memory to reduce SSTOREs
        DCAExecutionState memory state = executionStates[intentId];

        // Calculate total output amount
        uint256 totalOutput = 0;
        for (uint256 i = 0; i < outputs.length; i++) {
            totalOutput += outputs[i].amount;
        }

        // Update state in memory
        state.executedChunks++;
        state.lastExecutionTime = block.timestamp;
        state.totalInputExecuted += inputAmount;
        state.totalOutput += totalOutput;
        state.nextNonce++;

        // single SSTORE
        executionStates[intentId] = state;
    }

    /// @inheritdoc IDCAHook
    function computeIntentId(address swapper, uint256 nonce) external pure override returns (bytes32) {
        return keccak256(abi.encodePacked(swapper, nonce));
    }

    /// @inheritdoc IDCAHook
    function getExecutionState(bytes32 intentId) external view override returns (DCAExecutionState memory state) {
        return executionStates[intentId];
    }

    /// @inheritdoc IDCAHook
    function isIntentActive(bytes32 intentId, uint256 maxPeriod, uint256 deadline)
        external
        view
        override
        returns (bool active)
    {
        DCAExecutionState storage s = executionStates[intentId];
        if (s.cancelled) return false;
        if (deadline != 0 && block.timestamp > deadline) return false;
        if (s.executedChunks == 0) return true;
        if (maxPeriod != 0 && block.timestamp - s.lastExecutionTime > maxPeriod) return false;
        return true;
    }

    /// @inheritdoc IDCAHook
    function getNextNonce(bytes32 intentId) external view override returns (uint96 nextNonce) {
        return executionStates[intentId].nextNonce;
    }

    /// @inheritdoc IDCAHook
    function calculatePrice(uint256 inputAmount, uint256 outputAmount) external pure override returns (uint256 price) {
        if (inputAmount == 0) {
            revert ZeroInputAmount();
        }
        // Safely do (outputAmount * 1e18) / inputAmount
        return Math.mulDiv(outputAmount, 1e18, inputAmount);
    }

    /// @inheritdoc IDCAHook
    function getIntentStatistics(bytes32 intentId)
        external
        view
        override
        returns (
            uint256 totalChunks,
            uint256 totalInput,
            uint256 totalOutput,
            uint256 averagePrice,
            uint256 lastExecutionTime
        )
    {
        DCAExecutionState memory s = executionStates[intentId];
        totalChunks = s.executedChunks;
        totalInput = s.totalInputExecuted;
        totalOutput = s.totalOutput;
        lastExecutionTime = s.lastExecutionTime;
        averagePrice = totalInput == 0 ? 0 : Math.mulDiv(totalOutput, 1e18, totalInput);
    }
}
