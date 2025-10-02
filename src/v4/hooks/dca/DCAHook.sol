// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IDCAHook} from "../../interfaces/IDCAHook.sol";
import {IPreExecutionHook} from "../../interfaces/IHook.sol";
import {ResolvedOrder, InputToken, OutputToken} from "../../base/ReactorStructs.sol";
import {DCAIntent, DCAExecutionState, DCAOrderCosignerData, OutputAllocation, PermitData} from "./DCAStructs.sol";
import {DCALib} from "./DCALib.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {Permit2Lib} from "../../lib/Permit2Lib.sol";
import {IAuctionResolver} from "../../interfaces/IAuctionResolver.sol";
import {Math} from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {TokenTransferLib} from "../../lib/TokenTransferLib.sol";

/// @title DCAHook
/// @notice DCA hook implementation for UniswapX that validates and executes DCA intents
/// @dev Implements IPreExecutionHook for flexibility
contract DCAHook is IPreExecutionHook, IDCAHook {
    using Permit2Lib for ResolvedOrder;

    /// @notice Basis points constant (100% = 10000)
    uint256 private constant BPS = 10000;

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
        // 1) Decode pre-execution data
        (
            DCAIntent memory intent,
            bytes memory swapperSignature,
            bytes32 privateIntentHash,
            DCAOrderCosignerData memory cosignerData,
            bytes memory cosignerSignature,
            PermitData memory permitData
        ) = abi.decode(
            resolvedOrder.info.preExecutionHookData,
            (DCAIntent, bytes, bytes32, DCAOrderCosignerData, bytes, PermitData)
        );

        // 2) Compute intentId for state lookups
        bytes32 intentId = keccak256(abi.encodePacked(intent.swapper, intent.nonce));

        // 3) Validate the DCA intent
        _validateDCAIntent(
            intent, intentId, privateIntentHash, swapperSignature, cosignerData, cosignerSignature, resolvedOrder
        );

        // 4) Transfer input tokens with optional permit
        _transferInputTokens(resolvedOrder, filler, permitData);

        // 5) Update execution state and get cumulative totals
        (uint256 totalInputExecuted, uint256 totalOutputExecuted) =
            _updateExecutionState(intentId, resolvedOrder.input.amount, resolvedOrder.outputs);

        // 6) Emit executing chunk event
        emit ExecutingChunk(
            intentId, cosignerData.execAmount, cosignerData.limitAmount, totalInputExecuted, totalOutputExecuted
        );
    }

    /// @notice Validates DCA intent parameters and execution conditions
    /// @dev Performs all validation checks but does not modify state
    /// @param intent The decoded DCA intent
    /// @param intentId The computed intent identifier
    /// @param privateIntentHash The hash of private intent data
    /// @param swapperSignature The swapper's signature
    /// @param cosignerData The cosigner authorization data
    /// @param cosignerSignature The cosigner's signature
    /// @param resolvedOrder The resolved order to validate against
    function _validateDCAIntent(
        DCAIntent memory intent,
        bytes32 intentId,
        bytes32 privateIntentHash,
        bytes memory swapperSignature,
        DCAOrderCosignerData memory cosignerData,
        bytes memory cosignerSignature,
        ResolvedOrder calldata resolvedOrder
    ) internal view {
        // 1) Verify swapper signature (EIP-712) over full intent with privateIntentHash
        _validateSwapperSignature(intent, privateIntentHash, swapperSignature);

        // 2) Static field checks (binding correctness)
        _validateStaticFields(intent, resolvedOrder);

        // 3) Validate allocation structure (sum to 100%, no zeros)
        _validateAllocationStructure(intent.outputAllocations);

        // 4) Verify cosigner authorization
        _validateCosignerSignature(intent, cosignerData, cosignerSignature);

        // 5) State checks and period gating
        _validateStateAndTiming(intentId, intent, cosignerData);

        // 6) Chunk size checks
        _validateChunkSize(intent, cosignerData, resolvedOrder.input.amount);

        // 7) Price floor check (1e18 scaling)
        _validatePriceFloor(intent, cosignerData);

        // 8) Validate outputs match allocations and meet requirements
        _validateOutputDistribution(intent, cosignerData, resolvedOrder.outputs);
    }

    function _transferInputTokens(ResolvedOrder calldata order, address to, PermitData memory permitData) private {
        // If a permit signature is provided, set the allowance first
        if (permitData.hasPermit) {
            // Call permit directly since it's memory not calldata
            permit2.permit(order.info.swapper, permitData.permitSingle, permitData.signature);
        }

        // Transfer tokens using existing allowance (either just set or previously set)
        TokenTransferLib.allowanceTransferInputTokens(permit2, order, to);
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
    function _validateAllocationStructure(OutputAllocation[] memory outputAllocations) internal pure {
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
            if (totalBasisPoints > BPS) {
                revert AllocationsExceed100Percent();
            }

            unchecked {
                ++i;
            }
        }

        if (totalBasisPoints != BPS) {
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

    /// @notice Validates that actual outputs match expected distribution and meet limit requirements
    /// @dev Verifies outputs are distributed per allocations and total meets minimum/exact requirements
    /// @param intent The DCA intent containing allocation requirements
    /// @param cosignerData The cosigner data containing limit amounts
    /// @param outputs The actual outputs from the resolved order
    function _validateOutputDistribution(
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
            uint256 expected = Math.mulDiv(totalOutput, intent.outputAllocations[i].basisPoints, BPS);
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
    /// @return totalInputExecuted The cumulative input amount after this execution
    /// @return totalOutputExecuted The cumulative output amount after this execution
    function _updateExecutionState(bytes32 intentId, uint256 inputAmount, OutputToken[] memory outputs)
        internal
        returns (uint256 totalInputExecuted, uint256 totalOutputExecuted)
    {
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

        // Return cumulative totals for event emission
        return (state.totalInputExecuted, state.totalOutput);
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
