// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IDCARegistry} from "../interfaces/IDCARegistry.sol";
import {IValidationCallback} from "../interfaces/IValidationCallback.sol";
import {ResolvedOrder} from "../base/ReactorStructs.sol";
import {ECDSA} from "openzeppelin-contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "openzeppelin-contracts/utils/cryptography/EIP712.sol";

/// @notice Registry for tracking and validating DCA order execution with signature verification
contract DCARegistry is IDCARegistry, IValidationCallback, EIP712 {
    using ECDSA for bytes32;

    mapping(bytes32 => DCAExecutionState) public executionStates;
    mapping(address => mapping(uint256 => bool)) public usedNonces;
    mapping(bytes32 => bool) public usedOrderNonces;

    // Track registered intents to prevent replay attacks
    mapping(bytes32 => bool) public registeredIntents;

    error InvalidDCAFrequency();
    error InvalidDCAChunkSize();
    error DCAFloorPriceNotMet();
    error InvalidDCAParams();
    error InvalidSignature();
    error InvalidCosignature();
    error IntentExpired();
    error IntentAlreadyRegistered();
    error IntentNotRegistered();
    error NonceAlreadyUsed();
    error OrderNonceAlreadyUsed();
    error InvalidTokens();
    error InvalidCosigner();
    error InvalidauthorizationTimestamp();
    error InvalidGasPrice();

    /// @notice EIP-712 type hash for DCA intent
    bytes32 public constant DCA_INTENT_TYPEHASH = keccak256(
        "DCAIntent(address inputToken,address outputToken,address cosigner,uint256 minFrequency,uint256 maxFrequency,uint256 minChunkSize,uint256 maxChunkSize,uint256 minOutputAmount,uint256 maxSlippage,uint256 deadline,uint256 nonce,bytes32 privateIntentHash)"
    );

    constructor() EIP712("DCARegistry", "1") {}

    /// @inheritdoc IValidationCallback
    function validate(address, ResolvedOrder calldata order) external override {
        // Decode DCA validation data from additionalValidationData
        if (order.info.additionalValidationData.length == 0) {
            revert InvalidDCAParams();
        }

        bytes memory dcaData = order.info.additionalValidationData;

        // Skip AllowanceTransfer prefix if present
        if (dcaData.length > 0 && dcaData[0] == 0x01) {
            // Remove the first byte (AllowanceTransfer flag) and decode the rest
            bytes memory dcaValidationBytes = new bytes(dcaData.length - 1);
            for (uint256 i = 1; i < dcaData.length; i++) {
                dcaValidationBytes[i - 1] = dcaData[i];
            }
            dcaData = dcaValidationBytes;
        }

        DCAValidationData memory validationData = abi.decode(dcaData, (DCAValidationData));
        DCAIntent memory intent = validationData.intent;
        DCAOrderCosignerData memory cosignerData = validationData.cosignerData;

        // Calculate intent hash
        bytes32 intentHash = hashDCAIntent(intent);

        // Verify user signature if intent not already registered
        if (!registeredIntents[intentHash]) {
            _verifyIntentSignature(intent, validationData.signature, order.info.swapper);
            _registerIntent(intentHash, intent, order.info.swapper);
        }

        // Verify cosigner signature
        _verifyCosignerSignature(intent.cosigner, intentHash, cosignerData, validationData.cosignature);

        // Validate intent is still valid
        if (intent.deadline < block.timestamp) {
            revert IntentExpired();
        }

        // Validate execution timing
        if (cosignerData.authorizationTimestamp > block.timestamp + 300) {
            // Allow 5 min future buffer
            revert InvalidauthorizationTimestamp();
        }

        // Check order nonce hasn't been used
        if (usedOrderNonces[cosignerData.orderNonce]) {
            revert OrderNonceAlreadyUsed();
        }
        usedOrderNonces[cosignerData.orderNonce] = true;

        // Validate order matches intent parameters
        _validateOrderAgainstIntent(order, intent, cosignerData);

        // Update execution state
        DCAExecutionState storage state = executionStates[intentHash];

        // Check frequency constraints
        if (state.lastExecutionTime > 0) {
            uint256 timeSinceLastExecution = block.timestamp - state.lastExecutionTime;
            if (timeSinceLastExecution < intent.minFrequency || timeSinceLastExecution > intent.maxFrequency) {
                revert InvalidDCAFrequency();
            }
        }

        // Check chunk size constraints
        uint256 inputAmount = order.input.amount;
        if (inputAmount < intent.minChunkSize || inputAmount > intent.maxChunkSize) {
            revert InvalidDCAChunkSize();
        }

        // Verify cosigner-specified input amount matches order
        if (cosignerData.inputAmount != inputAmount) {
            revert InvalidDCAParams();
        }

        // Enforce user's minimum output amount requirement
        uint256 totalOutputAmount = 0;
        for (uint256 i = 0; i < order.outputs.length; i++) {
            if (order.outputs[i].token == intent.outputToken) {
                totalOutputAmount += order.outputs[i].amount;
            }
        }
        if (totalOutputAmount < intent.minOutputAmount) {
            revert DCAFloorPriceNotMet();
        }

        // Update state for next validation
        state.executedChunks++;
        state.lastExecutionTime = block.timestamp;
        state.totalInputExecuted += inputAmount;
    }

    /// @inheritdoc IDCARegistry
    function getExecutionState(bytes32 dcaIntentHash) external view override returns (DCAExecutionState memory) {
        return executionStates[dcaIntentHash];
    }

    /// @inheritdoc IDCARegistry
    function getDomainSeparator() external view override returns (bytes32) {
        return _domainSeparatorV4();
    }

    /// @inheritdoc IDCARegistry
    function hashDCAIntent(DCAIntent memory intent) public view override returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    DCA_INTENT_TYPEHASH,
                    intent.inputToken,
                    intent.outputToken,
                    intent.cosigner,
                    intent.minFrequency,
                    intent.maxFrequency,
                    intent.minChunkSize,
                    intent.maxChunkSize,
                    intent.minOutputAmount,
                    intent.maxSlippage,
                    intent.deadline,
                    intent.nonce,
                    intent.privateIntentHash
                )
            )
        );
    }

    /// @inheritdoc IDCARegistry
    function hashCosignerData(bytes32 intentHash, DCAOrderCosignerData memory cosignerData)
        external
        pure
        override
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(intentHash, abi.encode(cosignerData)));
    }

    /// @notice Register a DCA intent with signature verification
    /// @param intent The DCA intent to register
    /// @param signature User's signature over the intent
    function registerDCAIntent(DCAIntent memory intent, bytes memory signature) external {
        bytes32 intentHash = hashDCAIntent(intent);

        if (registeredIntents[intentHash]) {
            revert IntentAlreadyRegistered();
        }

        _verifyIntentSignature(intent, signature, msg.sender);
        _registerIntent(intentHash, intent, msg.sender);
    }

    /// @notice Internal function to verify DCA intent signature
    function _verifyIntentSignature(DCAIntent memory intent, bytes memory signature, address expectedSigner)
        internal
        view
    {
        // Check nonce hasn't been used
        if (usedNonces[expectedSigner][intent.nonce]) {
            revert NonceAlreadyUsed();
        }

        // Verify signature
        bytes32 hash = hashDCAIntent(intent);
        address signer = hash.recover(signature);

        if (signer != expectedSigner) {
            revert InvalidSignature();
        }
    }

    /// @notice Internal function to verify cosigner signature
    function _verifyCosignerSignature(
        address expectedCosigner,
        bytes32 intentHash,
        DCAOrderCosignerData memory cosignerData,
        bytes memory cosignature
    ) internal pure {
        if (expectedCosigner == address(0)) {
            revert InvalidCosigner();
        }

        bytes32 cosignerHash = keccak256(abi.encodePacked(intentHash, abi.encode(cosignerData)));

        (bytes32 r, bytes32 s) = abi.decode(cosignature, (bytes32, bytes32));
        uint8 v = uint8(cosignature[64]);
        address signer = ecrecover(cosignerHash, v, r, s);

        if (signer != expectedCosigner || signer == address(0)) {
            revert InvalidCosignature();
        }
    }

    /// @notice Internal function to register a DCA intent
    function _registerIntent(bytes32 intentHash, DCAIntent memory intent, address user) internal {
        registeredIntents[intentHash] = true;
        usedNonces[user][intent.nonce] = true;

        emit DCAIntentRegistered(intentHash, user, intent);
    }

    /// @notice Validate that the order parameters match the DCA intent and cosigner data
    function _validateOrderAgainstIntent(
        ResolvedOrder calldata order,
        DCAIntent memory intent,
        DCAOrderCosignerData memory cosignerData
    ) internal pure {
        // Validate input token matches
        if (address(order.input.token) != intent.inputToken) {
            revert InvalidTokens();
        }

        // Validate input amount matches cosigner specification
        if (order.input.amount != cosignerData.inputAmount) {
            revert InvalidDCAParams();
        }

        // Validate at least one output token matches intent
        bool validOutputFound = false;
        for (uint256 i = 0; i < order.outputs.length; i++) {
            if (order.outputs[i].token == intent.outputToken) {
                validOutputFound = true;
                break;
            }
        }
        if (!validOutputFound) {
            revert InvalidTokens();
        }
    }
}
