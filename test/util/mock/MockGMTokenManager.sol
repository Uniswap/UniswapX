// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {IGMTokenManager, Quote, QuoteSide} from "../../../src/external/IGMTokenManager.sol";

/// @notice Test mock of Ondo's GM token manager.
/// @dev Verifies an EIP-712 attestation signed by a trusted attestor, checks expiry, then mints
///      (transfers GM tokens out of its inventory) or redeems (transfers stablecoin out). All test
///      tokens are assumed to be 18 decimals; price is USD with 18 decimals, so the USD value of a
///      quote is `price * quantity / 1e18`.
contract MockGMTokenManager is IGMTokenManager {
    using SafeTransferLib for ERC20;

    error AttestationExpired();
    error InvalidAttestor();
    error AttestationAlreadyUsed();
    error InsufficientDeposit();

    bytes32 public constant QUOTE_TYPEHASH = keccak256(
        "Quote(uint256 chainId,uint256 attestationId,bytes32 userId,address asset,uint256 price,uint256 quantity,uint256 expiration,uint8 side,bytes32 additionalData)"
    );

    address public immutable attestor;
    bytes32 public immutable DOMAIN_SEPARATOR;

    mapping(uint256 => bool) public usedAttestation;

    constructor(address _attestor) {
        attestor = _attestor;
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("OndoGMTokenManager"),
                keccak256("1"),
                block.chainid,
                address(this)
            )
        );
    }

    /// @inheritdoc IGMTokenManager
    function mintWithAttestation(
        Quote calldata quote,
        bytes calldata signature,
        address depositToken,
        uint256 depositTokenAmount
    ) external returns (uint256) {
        _validate(quote, signature);
        // Require the deposit to cover the quoted USD cost (price * quantity).
        uint256 usdCost = (quote.price * quote.quantity) / 1e18;
        if (depositTokenAmount < usdCost) revert InsufficientDeposit();

        ERC20(depositToken).safeTransferFrom(msg.sender, address(this), depositTokenAmount);
        ERC20(quote.asset).safeTransfer(msg.sender, quote.quantity);
        return quote.quantity;
    }

    /// @inheritdoc IGMTokenManager
    function redeemWithAttestation(
        Quote calldata quote,
        bytes calldata signature,
        address receiveToken,
        uint256 minimumReceiveAmount
    ) external returns (uint256) {
        _validate(quote, signature);
        uint256 usdValue = (quote.price * quote.quantity) / 1e18;
        if (usdValue < minimumReceiveAmount) revert InsufficientDeposit();

        ERC20(quote.asset).safeTransferFrom(msg.sender, address(this), quote.quantity);
        ERC20(receiveToken).safeTransfer(msg.sender, usdValue);
        return usdValue;
    }

    function _validate(Quote calldata quote, bytes calldata signature) internal {
        if (block.timestamp > quote.expiration) revert AttestationExpired();
        if (usedAttestation[quote.attestationId]) revert AttestationAlreadyUsed();
        usedAttestation[quote.attestationId] = true;

        bytes32 structHash = keccak256(
            abi.encode(
                QUOTE_TYPEHASH,
                quote.chainId,
                quote.attestationId,
                quote.userId,
                quote.asset,
                quote.price,
                quote.quantity,
                quote.expiration,
                uint8(quote.side),
                quote.additionalData
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));

        (bytes32 r, bytes32 s) = abi.decode(signature, (bytes32, bytes32));
        uint8 v = uint8(signature[64]);
        address signer = ecrecover(digest, v, r, s);
        if (signer == address(0) || signer != attestor) revert InvalidAttestor();
    }
}
