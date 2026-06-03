// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/// @notice Direction of an Ondo Global Markets attestation quote
/// @dev BUY mints GM tokens (deposit stablecoin), SELL redeems GM tokens (receive stablecoin)
enum QuoteSide {
    BUY,
    SELL
}

/// @notice A signed quote authorizing a mint or redeem of an Ondo Global Markets (GM) token
/// @dev Fetched off-chain from Ondo's REST API (POST /v1/attestations) and signed by Ondo's attestor.
///      Mirrors the Quote struct expected by Ondo's GM token manager.
struct Quote {
    // The chain the quote is valid for
    uint256 chainId;
    // One-time-use identifier; prevents replay
    uint256 attestationId;
    // Identifier binding the quote to an on-chain wallet / KYC'd entity
    bytes32 userId;
    // The GM token being minted or redeemed (e.g. AAPLon)
    address asset;
    // Price per asset, expressed in USD with 18 decimals
    uint256 price;
    // Number of GM tokens for the transaction
    uint256 quantity;
    // Unix timestamp after which the quote is no longer valid
    uint256 expiration;
    // BUY for minting, SELL for redeeming
    QuoteSide side;
    // Extra encoded information carried with the quote
    bytes32 additionalData;
}

/// @notice Minimal interface for the Ondo Global Markets token manager
/// @dev See https://docs.ondo.finance/api-reference/smart-contracts
interface IGMTokenManager {
    /// @notice Mint GM tokens by depositing a stablecoin, authorized by a signed quote
    /// @param quote The attestation quote (side == BUY)
    /// @param signature The attestor's signature over the quote
    /// @param depositToken The stablecoin being deposited (USDon, USDC, or USDT)
    /// @param depositTokenAmount The amount of deposit token spent
    /// @return The amount of GM tokens minted to the caller
    function mintWithAttestation(
        Quote calldata quote,
        bytes calldata signature,
        address depositToken,
        uint256 depositTokenAmount
    ) external returns (uint256);

    /// @notice Redeem GM tokens for a stablecoin, authorized by a signed quote
    /// @param quote The attestation quote (side == SELL)
    /// @param signature The attestor's signature over the quote
    /// @param receiveToken The desired stablecoin output (USDon, USDC, or USDT)
    /// @param minimumReceiveAmount Slippage protection for the received amount
    /// @return The amount of stablecoin received by the caller
    function redeemWithAttestation(
        Quote calldata quote,
        bytes calldata signature,
        address receiveToken,
        uint256 minimumReceiveAmount
    ) external returns (uint256);
}
