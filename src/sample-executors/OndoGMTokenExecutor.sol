// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Owned} from "solmate/src/auth/Owned.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IReactorCallback} from "../interfaces/IReactorCallback.sol";
import {IReactor} from "../interfaces/IReactor.sol";
import {ResolvedOrder, SignedOrder} from "../base/ReactorStructs.sol";
import {IGMTokenManager, Quote, QuoteSide} from "../external/IGMTokenManager.sol";

/// @notice Example fill contract that just-in-time mints or redeems Ondo Global Markets (GM)
///         tokens to fill UniswapX Dutch orders, using off-chain attestations.
/// @dev The filler fetches a signed `Quote` from Ondo's REST API, then submits it as the order's
///      `callbackData`. During `reactorCallback` the reactor has already pulled the swapper's input
///      into this contract; this contract mints/redeems via the GM token manager and approves the
///      output token back to the reactor, which then sweeps it to the swapper. Because the reactor
///      enforces the signed order's output amounts in `_fill`, the swapper is protected regardless
///      of what `callbackData` contains.
///
///      This is a reference example. It is reactor-version-agnostic: V1/V2/V3 Dutch reactors all
///      share the same `executeWithCallback`/`reactorCallback` flow, so one executor (pinned to a
///      single reactor) works for any of them.
///
///      Funding model. The stablecoin deposited to Ondo on a mint (`OndoFill.stableToken` /
///      `stableAmount`) is sourced from THIS contract's balance — the contract never assumes it
///      came from the swapper. Two modes follow from that:
///        1. Swapper-funded (inventory-free): the order input IS the stablecoin Ondo wants, so the
///           swapper's input (pulled in by `_prepare`) funds the mint directly. Nothing is parked
///           here. This is the canonical buy-GM order.
///        2. Inventory-funded: the swapper pays a non-stable input (e.g. WETH). This contract fronts
///           the stablecoin from its own pre-funded balance to mint, and RETAINS the swapper's input
///           token as filler inventory (the owner rebalances/sweeps it out-of-band via
///           `withdrawERC20`). This keeps the executor swap-free at the cost of holding stablecoin
///           inventory; sourcing the stablecoin just-in-time (a swap leg or flash loan) is a
///           separate extension, intentionally not done here.
///      Redeem is symmetric: the swapper's GM token (input) is redeemed for stablecoin, which is
///      delivered as the output; any surplus stays as filler margin.
///
///      NOT handled here (production prerequisites, out of scope for this example):
///      - GM tokens are permissioned. The reactor -> swapper transfer in `_fill` will revert unless
///        the swapper is on Ondo's transfer allowlist. The filler must ensure swapper eligibility.
///      - `Quote.userId` binds the attestation to a KYC'd entity (typically this executor). The
///        attestor enforces that binding off-chain; nothing additional is checked on-chain here.
contract OndoGMTokenExecutor is IReactorCallback, Owned {
    using SafeTransferLib for ERC20;

    /// @notice thrown if execute is called by a non-whitelisted address
    error CallerNotWhitelisted();
    /// @notice thrown if reactorCallback is called by an address other than the reactor
    error MsgSenderNotReactor();

    /// @notice Whether to mint GM tokens (buy) or redeem them (sell) during the callback
    enum Action {
        MINT,
        REDEEM
    }

    /// @notice The data the filler ABI-encodes into the order's callbackData
    /// @dev `quote` and `signature` come straight from Ondo's attestation API
    struct OndoFill {
        // MINT (swapper buys GM token) or REDEEM (swapper sells GM token)
        Action action;
        // The Ondo attestation quote
        Quote quote;
        // The attestor signature over the quote
        bytes signature;
        // The stablecoin: deposited on MINT, received on REDEEM (USDon / USDC / USDT)
        address stableToken;
        // depositTokenAmount on MINT; minimumReceiveAmount on REDEEM
        uint256 stableAmount;
    }

    IReactor private immutable reactor;
    address private immutable whitelistedCaller;
    IGMTokenManager private immutable gmTokenManager;

    modifier onlyWhitelistedCaller() {
        if (msg.sender != whitelistedCaller) {
            revert CallerNotWhitelisted();
        }
        _;
    }

    modifier onlyReactor() {
        if (msg.sender != address(reactor)) {
            revert MsgSenderNotReactor();
        }
        _;
    }

    constructor(address _whitelistedCaller, IReactor _reactor, address _owner, IGMTokenManager _gmTokenManager)
        Owned(_owner)
    {
        whitelistedCaller = _whitelistedCaller;
        reactor = _reactor;
        gmTokenManager = _gmTokenManager;
    }

    /// @notice Execute a single order, JIT minting/redeeming GM tokens to fill it
    /// @param order The signed UniswapX order
    /// @param callbackData abi.encode(OndoFill) describing the mint/redeem to perform
    function execute(SignedOrder calldata order, bytes calldata callbackData) external onlyWhitelistedCaller {
        reactor.executeWithCallback(order, callbackData);
    }

    /// @notice Execute a batch of orders sharing the same callbackData
    function executeBatch(SignedOrder[] calldata orders, bytes calldata callbackData) external onlyWhitelistedCaller {
        reactor.executeBatchWithCallback(orders, callbackData);
    }

    /// @notice Called by the reactor mid-fill: input tokens are already held by this contract.
    ///         Mint or redeem GM tokens via Ondo, then approve the output token to the reactor.
    /// @param callbackData abi.encode(OndoFill)
    function reactorCallback(ResolvedOrder[] calldata, bytes calldata callbackData) external onlyReactor {
        OndoFill memory fill = abi.decode(callbackData, (OndoFill));

        if (fill.action == Action.MINT) {
            // Buy side: deposit stablecoin -> mint GM token. `fill.stableToken` is sourced from THIS
            // contract's balance regardless of what the swapper paid: it may be the swapper's input
            // (pulled in by _prepare when the input is the stablecoin), or pre-funded inventory when
            // the swapper paid a non-stable input. The order's input token is intentionally not read.
            ERC20(fill.stableToken).safeApprove(address(gmTokenManager), fill.stableAmount);
            gmTokenManager.mintWithAttestation(fill.quote, fill.signature, fill.stableToken, fill.stableAmount);
            // The minted GM token is the order output; approve it to the reactor for `_fill`.
            ERC20(fill.quote.asset).safeApprove(address(reactor), type(uint256).max);
        } else {
            // Sell side: the swapper's GM token input is already in this contract; approve it to the
            // GM token manager and redeem for stablecoin.
            ERC20(fill.quote.asset).safeApprove(address(gmTokenManager), fill.quote.quantity);
            gmTokenManager.redeemWithAttestation(fill.quote, fill.signature, fill.stableToken, fill.stableAmount);
            // The received stablecoin is the order output; approve it to the reactor for `_fill`.
            ERC20(fill.stableToken).safeApprove(address(reactor), type(uint256).max);
        }
    }

    /// @notice Sweep accumulated tokens (e.g. filler margin) to a recipient. Owner only.
    /// @param token The token to withdraw
    /// @param recipient The recipient of the tokens
    function withdrawERC20(ERC20 token, address recipient) external onlyOwner {
        token.safeTransfer(recipient, token.balanceOf(address(this)));
    }
}
