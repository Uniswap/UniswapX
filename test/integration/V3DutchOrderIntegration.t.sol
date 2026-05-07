// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {V3DutchOrderReactor} from "../../src/reactors/V3DutchOrderReactor.sol";
import {
    V3DutchOrder,
    V3DutchOrderLib,
    V3DutchInput,
    V3DutchOutput,
    CosignerData,
    NonlinearDutchDecay
} from "../../src/lib/V3DutchOrderLib.sol";
import {OrderInfo, SignedOrder, ResolvedOrder} from "../../src/base/ReactorStructs.sol";
import {OrderQuoter} from "../../src/lens/OrderQuoter.sol";
import {OrderInfoBuilder} from "../util/OrderInfoBuilder.sol";
import {CurveBuilder} from "../util/CurveBuilder.sol";
import {PermitSignature} from "../util/PermitSignature.sol";
import {MockERC20} from "../util/mock/MockERC20.sol";

/// @title V3DutchOrderIntegrationTest
///
/// Sanity + end-to-end integration tests for a deployed V3DutchOrderReactor +
/// OrderQuoter pair. The chain, contract addresses, swapper/filler private
/// keys, and trade params are all driven by .env so the same suite can run
/// against Tempo, Arbitrum, or any future chain we deploy V3 to.
///
/// Three tiers of tests:
///   1. Sanity (always runs when forked): contracts have code, reactor is
///      bound to the canonical Permit2.
///   2. Off-chain quote (always runs when forked): build + sign + cosign a V3
///      order and resolve it via the OrderQuoter lens. Verifies the full
///      sign/cosign/permit2/resolve path against a live reactor.
///   3. End-to-end fill (always runs when forked): signs + cosigns the order,
///      fills it from the filler EOA via direct fill, asserts token deltas.
///
/// Tier-2 and tier-3 deploy fresh `MockERC20` contracts on the fork and use
/// those as the input/output tokens. We do this because some chains' native
/// stablecoins (e.g. Tempo's TIP-20 tokens at `0x20c0...`) use chain-specific
/// opcodes that revert with `OpcodeNotFound` under Foundry's local EVM —
/// `transferFrom` simply doesn't work in a fork. Mocks are the canonical
/// foundry pattern for this. The reactor is real; only the trade tokens are
/// substituted.
///
/// Required env (always):
///   FOUNDRY_RPC_URL              chain RPC. Without this the suite is skipped.
///
/// Optional env (with Tempo defaults so the suite runs out of the box):
///   INTEGRATION_REACTOR          V3DutchOrderReactor address on the target chain
///   INTEGRATION_QUOTER           OrderQuoter address
///   DEPLOYER_MNEMONIC            BIP-39 seed phrase. When set, swapper / filler /
///                                cosigner are derived at HD indexes 1 / 2 / 3
///                                (index 0 is the deployer EOA itself, kept for
///                                broadcast scripts). When unset, deterministic
///                                keys derived from keccak256("integration-...")
///                                are used so the suite still runs without
///                                configured EOAs. Either way, no real funds
///                                are needed — tier-2/3 deploy MockERC20s and
///                                `deal()` token balances onto the fork.
///   INTEGRATION_AMOUNT_IN        default 1_000_000 (raw units)
///   INTEGRATION_AMOUNT_OUT       default   999_000 (raw units; 0.1% spread)
///
/// Run:
///   FOUNDRY_RPC_URL=https://rpc.tempo.xyz \
///   FOUNDRY_PROFILE=integration forge test --match-contract V3DutchOrderIntegrationTest -vv
contract V3DutchOrderIntegrationTest is Test, PermitSignature {
    using OrderInfoBuilder for OrderInfo;
    using V3DutchOrderLib for V3DutchOrder;

    // Tempo defaults. Reactor is the per-AMM-governance redeploy
    // (PoolManager.owner() = 0xCFB43dC5...811b) — supersedes the original
    // ECO-365 phase 1b reactor at 0x000000005aF6... which had the wrong owner
    // and is now inert on Tempo. Quoter is the original from phase 1b
    // (stateless, no governance, unaffected by the reactor redeploy).
    address constant DEFAULT_REACTOR = 0x00000000fc1E66C9f582566EAd00108e55F1c0C6;
    address constant DEFAULT_QUOTER = 0x00000000a3db63Df9078cBF3dF88B4CAdD5a7F58;
    address constant CANONICAL_PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // HD derivation indexes for tier-2/tier-3 EOAs when DEPLOYER_MNEMONIC is
    // set. Index 0 is reserved for the deployer (used by the broadcast
    // scripts), so test EOAs start at 1 to avoid stomping on a wallet that
    // may hold real funds.
    uint32 constant SWAPPER_HD_INDEX = 1;
    uint32 constant FILLER_HD_INDEX = 2;
    uint32 constant COSIGNER_HD_INDEX = 3;

    bool internal forked;
    V3DutchOrderReactor internal reactor;
    OrderQuoter internal quoter;
    IPermit2 internal permit2;

    uint256 internal swapperPK;
    address internal swapper;
    uint256 internal fillerPK;
    address internal filler;
    uint256 internal cosignerPK;
    address internal cosigner;

    function setUp() public {
        // Skip the entire suite if no fork RPC is configured. Mirrors the
        // existing UniversalRouterExecutorIntegration.t.sol pattern.
        try vm.envString("FOUNDRY_RPC_URL") returns (string memory rpc) {
            // Tempo's 500ms block time means public RPCs may prune state
            // faster than forge's fork-cache resolves; pin to a specific
            // block so account lookups stay coherent. Override via
            // INTEGRATION_FORK_BLOCK if running against another chain.
            uint256 forkBlock = _envUintOrDefault("INTEGRATION_FORK_BLOCK", 0);
            if (forkBlock == 0) {
                vm.createSelectFork(rpc);
            } else {
                vm.createSelectFork(rpc, forkBlock);
            }
            forked = true;
        } catch {
            console2.log("FOUNDRY_RPC_URL unset; integration tests skipped.");
            forked = false;
            return;
        }

        address reactorAddr = _envAddressOrDefault("INTEGRATION_REACTOR", DEFAULT_REACTOR);
        address quoterAddr = _envAddressOrDefault("INTEGRATION_QUOTER", DEFAULT_QUOTER);
        reactor = V3DutchOrderReactor(payable(reactorAddr));
        quoter = OrderQuoter(payable(quoterAddr));
        permit2 = IPermit2(CANONICAL_PERMIT2);

        // Arbitrum-only: the reactor's `BlockNumberish` mixin captures the
        // chainid at deploy time and routes block-number reads through the
        // ArbSys precompile (0x64) on chain 42161. Foundry's local EVM
        // doesn't implement Arbitrum precompiles, so any forked call from
        // the reactor that needs a block number reverts with InvalidFEOpcode.
        // Mock the precompile to return the L1 block number — the test
        // orders don't have meaningful decay (start == end), so the value
        // only needs to be non-reverting and monotonic.
        if (block.chainid == 42161) {
            vm.mockCall(
                address(0x64),
                abi.encodeWithSignature("arbBlockNumber()"),
                abi.encode(block.number)
            );
        }

        // Derive tier-2/3 EOAs from DEPLOYER_MNEMONIC at indexes 1/2/3 when
        // it's set. Otherwise fall back to deterministic keccak-derived keys
        // so the suite still runs without env config. The cosigner is always
        // a test key — tier-3 sets the order's `cosigner` field to its derived
        // address, so the cosignature validates without needing the
        // production cosigner key on the test machine.
        swapperPK = _deriveOrFallback(SWAPPER_HD_INDEX, uint256(keccak256("integration-swapper")));
        swapper = vm.addr(swapperPK);
        vm.label(swapper, "swapper");

        fillerPK = _deriveOrFallback(FILLER_HD_INDEX, uint256(keccak256("integration-filler")));
        filler = vm.addr(fillerPK);
        vm.label(filler, "filler");

        cosignerPK = _deriveOrFallback(COSIGNER_HD_INDEX, uint256(keccak256("integration-cosigner")));
        cosigner = vm.addr(cosignerPK);
        vm.label(cosigner, "cosigner");
    }

    // ---------- tier 1: sanity ----------

    function test_sanity_reactorHasCode() public view {
        if (!forked) return;
        assertGt(address(reactor).code.length, 0, "reactor: no code at expected address");
    }

    function test_sanity_reactorBoundToCanonicalPermit2() public view {
        if (!forked) return;
        assertEq(address(reactor.permit2()), CANONICAL_PERMIT2, "reactor not bound to canonical Permit2");
    }

    function test_sanity_quoterHasCode() public view {
        if (!forked) return;
        // `setUp` either binds to a configured quoter (with code) or
        // fork-deploys a fresh one — either way `quoter.code` must be
        // non-empty for tier-2 tests to do anything meaningful.
        assertGt(address(quoter).code.length, 0, "quoter has no code (setup invariant)");
    }

    function test_sanity_permit2HasCode() public view {
        if (!forked) return;
        assertGt(CANONICAL_PERMIT2.code.length, 0, "permit2: not deployed at canonical address on target chain");
    }

    // ---------- tier 2: off-chain order resolution ----------

    /// Resolves a freshly-built V3 order through the OrderQuoter lens.
    /// Exercises the full sign + cosign + permit2 + resolve path on a real
    /// reactor + quoter pair. Uses fork-deployed mock ERC20s as trade tokens
    /// (see contract header).
    function test_resolveOrder_offchain() public {
        if (!forked) return;
        require(swapper != filler, "swapper and filler must differ; set distinct INTEGRATION_*_PK");

        (address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut) = _setupTrade();

        SignedOrder memory signed = _buildSignedOrder(tokenIn, tokenOut, amountIn, amountOut);
        ResolvedOrder memory resolved = quoter.quote(signed.order, signed.sig);

        assertEq(address(resolved.input.token), tokenIn, "resolved input token mismatch");
        assertEq(resolved.outputs[0].token, tokenOut, "resolved output token mismatch");
        assertEq(resolved.input.amount, amountIn, "resolved input amount mismatch (no decay configured)");
        assertEq(resolved.outputs[0].amount, amountOut, "resolved output amount mismatch (no decay configured)");
        assertEq(resolved.outputs[0].recipient, swapper, "recipient should be swapper");
    }

    // ---------- tier 3: end-to-end fill ----------

    /// Full sign → fill round-trip against the live reactor. Uses fork-
    /// deployed mock ERC20s + `deal()` to mint balances; does not move real
    /// chain state. Asserts the swapper's tokenIn decreased by amountIn, the
    /// swapper's tokenOut increased by amountOut, and the filler's balances
    /// mirror.
    function test_fillOrder_endToEnd() public {
        if (!forked) return;
        require(swapper != filler, "swapper and filler must differ; set distinct INTEGRATION_*_PK");

        (address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut) = _setupTrade();

        SignedOrder memory signed = _buildSignedOrder(tokenIn, tokenOut, amountIn, amountOut);

        uint256 swapperInBefore = ERC20(tokenIn).balanceOf(swapper);
        uint256 swapperOutBefore = ERC20(tokenOut).balanceOf(swapper);
        uint256 fillerInBefore = ERC20(tokenIn).balanceOf(filler);
        uint256 fillerOutBefore = ERC20(tokenOut).balanceOf(filler);

        vm.prank(filler);
        reactor.execute(signed);

        assertEq(ERC20(tokenIn).balanceOf(swapper), swapperInBefore - amountIn, "swapper tokenIn unchanged");
        assertEq(ERC20(tokenOut).balanceOf(swapper), swapperOutBefore + amountOut, "swapper did not receive tokenOut");
        assertEq(ERC20(tokenIn).balanceOf(filler), fillerInBefore + amountIn, "filler did not receive tokenIn");
        assertEq(ERC20(tokenOut).balanceOf(filler), fillerOutBefore - amountOut, "filler tokenOut unchanged");
    }

    /// Deploy fresh mock ERC20s on the fork, mint balances to swapper/filler,
    /// and wire up the permit2 + reactor approvals. Returns the token
    /// addresses + amounts ready to be passed into the order builder.
    function _setupTrade() internal returns (address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut) {
        amountIn = _envUintOrDefault("INTEGRATION_AMOUNT_IN", 1_000_000);
        amountOut = _envUintOrDefault("INTEGRATION_AMOUNT_OUT", 999_000);

        MockERC20 inMock = new MockERC20("MockTokenIn", "MIN", 6);
        MockERC20 outMock = new MockERC20("MockTokenOut", "MOUT", 6);
        tokenIn = address(inMock);
        tokenOut = address(outMock);

        inMock.mint(swapper, amountIn);
        outMock.mint(filler, amountOut);

        vm.prank(swapper);
        ERC20(tokenIn).approve(CANONICAL_PERMIT2, type(uint256).max);

        vm.prank(filler);
        ERC20(tokenOut).approve(address(reactor), type(uint256).max);
    }

    // ---------- helpers ----------

    /// Build a single-input single-output V3 order with no decay (start ==
    /// end) so resolved amounts are deterministic and don't depend on the
    /// fork block number. Signed by `swapperPK`, cosigned by `cosignerPK`.
    function _buildSignedOrder(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut)
        internal
        view
        returns (SignedOrder memory)
    {
        V3DutchOutput[] memory outs = new V3DutchOutput[](1);
        outs[0] = V3DutchOutput({
            token: tokenOut,
            startAmount: amountOut,
            curve: CurveBuilder.emptyCurve(),
            recipient: swapper,
            minAmount: amountOut,
            adjustmentPerGweiBaseFee: 0
        });

        uint256[] memory cosignerOutAmounts = new uint256[](1);
        cosignerOutAmounts[0] = 0;

        CosignerData memory cd = CosignerData({
            decayStartBlock: block.number,
            exclusiveFiller: address(0),
            exclusivityOverrideBps: 0,
            inputAmount: 0,
            outputAmounts: cosignerOutAmounts
        });

        V3DutchOrder memory order = V3DutchOrder({
            info: OrderInfoBuilder.init(address(reactor)).withSwapper(swapper).withDeadline(block.timestamp + 1000),
            cosigner: cosigner,
            baseInput: V3DutchInput({
                token: ERC20(tokenIn),
                startAmount: amountIn,
                curve: CurveBuilder.emptyCurve(),
                maxAmount: amountIn,
                adjustmentPerGweiBaseFee: 0
            }),
            baseOutputs: outs,
            cosignerData: cd,
            cosignature: bytes(""),
            startingBaseFee: block.basefee
        });

        bytes32 orderHash = order.hash();
        order.cosignature = _cosign(orderHash, cd);
        bytes memory swapperSig = signOrder(swapperPK, address(permit2), order);
        return SignedOrder(abi.encode(order), swapperSig);
    }

    function _cosign(bytes32 orderHash, CosignerData memory cd) internal view returns (bytes memory) {
        bytes32 msgHash = keccak256(abi.encodePacked(orderHash, block.chainid, abi.encode(cd)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(cosignerPK, msgHash);
        return bytes.concat(r, s, bytes1(v));
    }

    function _envAddressOrDefault(string memory key, address fallback_) internal view returns (address) {
        try vm.envAddress(key) returns (address a) {
            return a;
        } catch {
            return fallback_;
        }
    }

    function _envUintOrDefault(string memory key, uint256 fallback_) internal view returns (uint256) {
        try vm.envUint(key) returns (uint256 v) {
            return v;
        } catch {
            return fallback_;
        }
    }

    /// Derive a key from DEPLOYER_MNEMONIC at the given HD index, or return
    /// `fallback_` (deterministic keccak-derived) when the mnemonic is unset.
    /// Wrapped in a try/catch because `vm.deriveKey` reverts on a missing or
    /// malformed mnemonic, and we want the suite to keep running with the
    /// fallback in that case.
    function _deriveOrFallback(uint32 hdIndex, uint256 fallback_) internal view returns (uint256) {
        try vm.envString("DEPLOYER_MNEMONIC") returns (string memory mnemonic) {
            if (bytes(mnemonic).length == 0) return fallback_;
            try vm.deriveKey(mnemonic, hdIndex) returns (uint256 pk) {
                return pk;
            } catch {
                return fallback_;
            }
        } catch {
            return fallback_;
        }
    }
}
