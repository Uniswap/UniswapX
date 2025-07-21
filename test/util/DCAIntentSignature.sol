// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {ECDSA} from "openzeppelin-contracts/utils/cryptography/ECDSA.sol";
import {IDCARegistry} from "../../src/interfaces/IDCARegistry.sol";

/// @notice Utility for signing DCA intents and cosigner data in tests and integrations
contract DCAIntentSignature is Test {
    using ECDSA for bytes32;

    /// @notice Create a signature for a DCA intent
    /// @param intent The DCA intent to sign
    /// @param privateKey The private key to sign with
    /// @param dcaRegistry The DCA registry to get domain separator from
    /// @return signature The EIP-712 signature
    function signDCAIntent(IDCARegistry.DCAIntent memory intent, uint256 privateKey, IDCARegistry dcaRegistry)
        public
        view
        returns (bytes memory signature)
    {
        bytes32 hash = dcaRegistry.hashDCAIntent(intent);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);
        return bytes.concat(r, s, bytes1(v));
    }

    /// @notice Create a cosigner signature for specific order execution
    /// @param intentHash Hash of the DCA intent
    /// @param cosignerData The cosigner data to sign
    /// @param cosignerPrivateKey The cosigner's private key
    /// @return signature The cosigner signature
    function signCosignerData(
        bytes32 intentHash,
        IDCARegistry.DCAOrderCosignerData memory cosignerData,
        uint256 cosignerPrivateKey
    ) public view returns (bytes memory signature) {
        bytes32 hash = keccak256(abi.encodePacked(intentHash, abi.encode(cosignerData)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(cosignerPrivateKey, hash);
        return bytes.concat(r, s, bytes1(v));
    }

    /// @notice Helper to create a basic DCA intent for testing
    /// @param inputToken Token to sell
    /// @param outputToken Token to buy
    /// @param cosigner Trusted cosigner address
    /// @param user User address
    /// @param nonce User nonce for replay protection
    /// @return intent A basic DCA intent with reasonable defaults
    function createBasicDCAIntent(
        address inputToken,
        address outputToken,
        address cosigner,
        address user,
        uint256 nonce
    ) public view returns (IDCARegistry.DCAIntent memory intent) {
        intent = IDCARegistry.DCAIntent({
            inputToken: inputToken,
            outputToken: outputToken,
            cosigner: cosigner,
            minFrequency: 1 hours,
            maxFrequency: 24 hours,
            minChunkSize: 100e18, // 100 tokens
            maxChunkSize: 1000e18, // 1000 tokens
            minOutputPricePerInput: 0, // No minimum price
            maxSlippage: 500, // 5% max slippage
            deadline: block.timestamp + 30 days,
            nonce: nonce,
            privateIntentHash: keccak256(abi.encode(user, "private", nonce))
        });
    }

    /// @notice Helper to create cosigner data for testing
    /// @param inputAmount Input amount for this execution
    /// @param minOutputAmount Minimum output expected
    /// @param orderNonce Unique order nonce
    /// @return cosignerData Basic cosigner data
    function createBasicCosignerData(uint256 inputAmount, uint256 minOutputAmount, bytes32 orderNonce)
        public
        view
        returns (IDCARegistry.DCAOrderCosignerData memory cosignerData)
    {
        cosignerData = IDCARegistry.DCAOrderCosignerData({
            executionTimestamp: block.timestamp,
            inputAmount: inputAmount,
            minOutputAmount: minOutputAmount,
            orderNonce: orderNonce
        });
    }

    /// @notice Create complete DCA validation data with signatures
    /// @param intent The DCA intent
    /// @param cosignerData The cosigner data
    /// @param userPrivateKey User's private key
    /// @param cosignerPrivateKey Cosigner's private key
    /// @param dcaRegistry The DCA registry
    /// @return validationData Complete validation data with signatures
    function createSignedDCAValidationData(
        IDCARegistry.DCAIntent memory intent,
        IDCARegistry.DCAOrderCosignerData memory cosignerData,
        uint256 userPrivateKey,
        uint256 cosignerPrivateKey,
        IDCARegistry dcaRegistry
    ) public view returns (IDCARegistry.DCAValidationData memory validationData) {
        bytes32 intentHash = dcaRegistry.hashDCAIntent(intent);

        validationData = IDCARegistry.DCAValidationData({
            intent: intent,
            signature: signDCAIntent(intent, userPrivateKey, dcaRegistry),
            cosignerData: cosignerData,
            cosignature: signCosignerData(intentHash, cosignerData, cosignerPrivateKey)
        });
    }
}
