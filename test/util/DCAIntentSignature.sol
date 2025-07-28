// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {ECDSA} from "openzeppelin-contracts/utils/cryptography/ECDSA.sol";
import {IDCARegistry} from "../../src/interfaces/IDCARegistry.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {IEIP712} from "permit2/src/interfaces/IEIP712.sol";

/// @notice Utility for signing DCA intents and cosigner data in tests and integrations
contract DCAIntentSignature is Test {
    using ECDSA for bytes32;

    struct PrivateDCAParams {
        uint256 totalAmount;
        uint256 expectedChunks;
        uint256 maxTotalSlippage;
        bytes32 salt;
    }

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
    ) public pure returns (bytes memory signature) {
        bytes32 hash = keccak256(abi.encodePacked(intentHash, abi.encode(cosignerData)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(cosignerPrivateKey, hash);
        return bytes.concat(r, s, bytes1(v));
    }

    function hashPrivateDCAParams(PrivateDCAParams memory params) public pure returns (bytes32) {
        return keccak256(abi.encode(params));
    }

    function createPrivateDCAParams(uint256 totalAmount, uint256 expectedChunks, uint256 maxTotalSlippage, bytes32 salt)
        public
        pure
        returns (PrivateDCAParams memory)
    {
        return PrivateDCAParams({
            totalAmount: totalAmount,
            expectedChunks: expectedChunks,
            maxTotalSlippage: maxTotalSlippage,
            salt: salt
        });
    }

    function createPublicDCAIntent(address inputToken, address outputToken, address cosigner, bytes32 privateIntentHash)
        public
        view
        returns (IDCARegistry.DCAIntent memory intent)
    {
        intent = IDCARegistry.DCAIntent({
            inputToken: inputToken,
            outputToken: outputToken,
            cosigner: cosigner,
            minFrequency: 1 hours,
            maxFrequency: 24 hours,
            minChunkSize: 100e18, // 100 tokens
            maxChunkSize: 1000e18, // 1000 tokens
            minOutputAmount: 0, // No minimum output amount
            maxSlippage: 500, // 5% max slippage
            deadline: block.timestamp + 30 days,
            privateIntentHash: privateIntentHash
        });
    }

    /// @notice Helper to create cosigner data for testing
    /// @param swapper The actual swapper (user) address
    /// @param inputAmount Input amount for this execution
    /// @param minOutputAmount Minimum output expected
    /// @param orderNonce Unique order nonce
    /// @return cosignerData Basic cosigner data
    function createBasicCosignerData(address swapper, uint256 inputAmount, uint256 minOutputAmount, bytes32 orderNonce)
        public
        view
        returns (IDCARegistry.DCAOrderCosignerData memory cosignerData)
    {
        cosignerData = IDCARegistry.DCAOrderCosignerData({
            swapper: swapper,
            authorizationTimestamp: block.timestamp,
            inputAmount: inputAmount,
            minOutputAmount: minOutputAmount,
            orderNonce: orderNonce
        });
    }

    bytes32 private constant PERMIT_DETAILS_TYPEHASH =
        keccak256("PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)");
    bytes32 private constant PERMIT_SINGLE_TYPEHASH = keccak256(
        "PermitSingle(PermitDetails details,address spender,uint256 sigDeadline)PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)"
    );

    function _hashPermitSingle(IAllowanceTransfer.PermitSingle memory permit) internal pure returns (bytes32 hash) {
        bytes32 detailsHash = keccak256(
            abi.encode(
                PERMIT_DETAILS_TYPEHASH,
                permit.details.token,
                permit.details.amount,
                permit.details.expiration,
                permit.details.nonce
            )
        );
        hash = keccak256(abi.encode(PERMIT_SINGLE_TYPEHASH, detailsHash, permit.spender, permit.sigDeadline));
    }

    /// @notice Create full validation data including PermitSingle and signatures
    function createSignedDCAValidationData(
        IDCARegistry.DCAIntent memory intent,
        IDCARegistry.DCAOrderCosignerData memory cosignerData,
        uint256 swapperPrivateKey,
        uint256 cosignerPrivateKey,
        IDCARegistry dcaRegistry,
        IAllowanceTransfer permit2
    ) public view returns (IDCARegistry.DCAValidationData memory validationData) {
        bytes32 intentHash = dcaRegistry.hashDCAIntent(intent);

        // Build PermitSingle granting max allowance to registry
        IAllowanceTransfer.PermitSingle memory permit;
        permit.details = IAllowanceTransfer.PermitDetails({
            token: intent.inputToken,
            amount: type(uint160).max,
            expiration: uint48(intent.deadline),
            nonce: 0
        });
        permit.spender = address(dcaRegistry);
        permit.sigDeadline = intent.deadline;

        // Compute permit digest per EIP712 from Permit2
        bytes32 permitHash = _hashPermitSingle(permit);
        bytes32 domainSeparator = IEIP712(address(permit2)).DOMAIN_SEPARATOR();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, permitHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(swapperPrivateKey, digest);
        bytes memory permitSig = bytes.concat(r, s, bytes1(v));

        validationData = IDCARegistry.DCAValidationData({
            intent: intent,
            signature: signDCAIntent(intent, swapperPrivateKey, dcaRegistry),
            cosignerData: cosignerData,
            cosignature: signCosignerData(intentHash, cosignerData, cosignerPrivateKey),
            permit: permit,
            permitSignature: permitSig
        });
    }
}
