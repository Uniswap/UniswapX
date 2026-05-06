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
///      order and resolve it via the OrderQuoter lens. Does not require token
///      balances or approvals; verifies cosigning and decay math against a
///      live reactor.
///   3. End-to-end fill (runs when INTEGRATION_TOKEN_IN/OUT + AMOUNT_*
///      are set): mints tokenIn to the swapper via `deal()` (fork-only,
///      doesn't touch mainnet state), signs + cosigns the order, fills it
///      from the filler EOA via direct fill, and asserts post-state token
///      balances.
///
/// Required env (always):
///   FOUNDRY_RPC_URL              chain RPC. Without this the suite is skipped.
///
/// Optional env (with Tempo defaults so the suite runs out of the box):
///   INTEGRATION_REACTOR          V3DutchOrderReactor address on the target chain
///   INTEGRATION_QUOTER           OrderQuoter address
///   INTEGRATION_SWAPPER_PK       swapper EIP-712 signing key
///   INTEGRATION_FILLER_PK        filler EOA key (may equal swapper)
///   INTEGRATION_COSIGNER_PK      cosigner key. If unset, a deterministic
///                                test key is used and the order's cosigner
///                                field is set to its derived address — this
///                                is what makes the test fully self-contained
///                                without needing a production cosigner key.
///
/// Required env for tier-3 fill (skipped if any are missing):
///   INTEGRATION_TOKEN_IN         ERC20 input token
///   INTEGRATION_TOKEN_OUT        ERC20 output token
///   INTEGRATION_AMOUNT_IN        amount swapper sends (raw units)
///   INTEGRATION_AMOUNT_OUT       amount filler delivers (raw units)
///
/// Run:
///   FOUNDRY_RPC_URL=https://rpc.tempo.xyz \
///   INTEGRATION_SWAPPER_PK=0x... \
///   INTEGRATION_FILLER_PK=0x... \
///   INTEGRATION_TOKEN_IN=0x... \
///   INTEGRATION_TOKEN_OUT=0x... \
///   INTEGRATION_AMOUNT_IN=1000000 \
///   INTEGRATION_AMOUNT_OUT=999000 \
///   FOUNDRY_PROFILE=integration forge test --match-contract V3DutchOrderIntegrationTest -vv
contract V3DutchOrderIntegrationTest is Test, PermitSignature {
    using OrderInfoBuilder for OrderInfo;
    using V3DutchOrderLib for V3DutchOrder;

    // Tempo defaults — pinned to the live deployments from ECO-365 phase 1b.
    address constant DEFAULT_REACTOR = 0x000000005aF66799D1a6317714D66800f9CA1406;
    address constant DEFAULT_QUOTER = 0x00000000a3db63Df9078cBF3dF88B4CAdD5a7F58;
    address constant CANONICAL_PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // Deterministic fallback cosigner so the suite can run without a real
    // cosigner key. The key never controls real funds — it's only used to
    // produce a valid cosignature for an order whose `cosigner` field we
    // set to its derived address.
    uint256 constant FALLBACK_COSIGNER_PK = 0xC0517E4;

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
            vm.createSelectFork(rpc);
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

        swapperPK = _envUintOrDefault("INTEGRATION_SWAPPER_PK", uint256(keccak256("integration-swapper")));
        swapper = vm.addr(swapperPK);
        vm.label(swapper, "swapper");

        fillerPK = _envUintOrDefault("INTEGRATION_FILLER_PK", uint256(keccak256("integration-filler")));
        filler = vm.addr(fillerPK);
        vm.label(filler, "filler");

        cosignerPK = _envUintOrDefault("INTEGRATION_COSIGNER_PK", FALLBACK_COSIGNER_PK);
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
        assertGt(address(quoter).code.length, 0, "quoter: no code at expected address");
    }

    function test_sanity_permit2HasCode() public view {
        if (!forked) return;
        assertGt(CANONICAL_PERMIT2.code.length, 0, "permit2: not deployed at canonical address on target chain");
    }

    // ---------- tier 2: off-chain order resolution ----------

    /// Resolves a freshly-built V3 order through the OrderQuoter lens. Doesn't
    /// require any token balances — just exercises the full sign + cosign +
    /// resolve path on a real reactor + quoter pair.
    function test_resolveOrder_offchain() public {
        if (!forked) return;

        (address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut) = _readTradeOrSkip();
        if (tokenIn == address(0)) return; // graceful skip if trade env not provided

        SignedOrder memory signed = _buildSignedOrder(tokenIn, tokenOut, amountIn, amountOut);
        ResolvedOrder memory resolved = quoter.quote(signed.order, signed.sig);

        assertEq(address(resolved.input.token), tokenIn, "resolved input token mismatch");
        assertEq(resolved.outputs[0].token, tokenOut, "resolved output token mismatch");
        assertEq(resolved.input.amount, amountIn, "resolved input amount mismatch (no decay configured)");
        assertEq(resolved.outputs[0].amount, amountOut, "resolved output amount mismatch (no decay configured)");
        assertEq(resolved.outputs[0].recipient, swapper, "recipient should be swapper");
    }

    // ---------- tier 3: end-to-end fill ----------

    /// Full sign → fill round-trip against the live reactor. Uses `deal()` to
    /// mint balances on the fork — does not move real chain state. Asserts
    /// the swapper's tokenIn decreased by amountIn, the swapper's tokenOut
    /// increased by amountOut, and the filler's balances mirror.
    function test_fillOrder_endToEnd() public {
        if (!forked) return;

        (address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut) = _readTradeOrSkip();
        if (tokenIn == address(0)) return;

        // Mint test balances on the fork.
        deal(tokenIn, swapper, amountIn);
        deal(tokenOut, filler, amountOut);

        // Swapper grants Permit2 allowance for tokenIn.
        vm.startPrank(swapper);
        ERC20(tokenIn).approve(CANONICAL_PERMIT2, type(uint256).max);
        vm.stopPrank();

        // Filler grants reactor allowance for tokenOut (direct-fill path).
        vm.startPrank(filler);
        ERC20(tokenOut).approve(address(reactor), type(uint256).max);
        vm.stopPrank();

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

    function _readTradeOrSkip()
        internal
        view
        returns (address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut)
    {
        try vm.envAddress("INTEGRATION_TOKEN_IN") returns (address t) {
            tokenIn = t;
        } catch {
            return (address(0), address(0), 0, 0);
        }
        try vm.envAddress("INTEGRATION_TOKEN_OUT") returns (address t) {
            tokenOut = t;
        } catch {
            return (address(0), address(0), 0, 0);
        }
        try vm.envUint("INTEGRATION_AMOUNT_IN") returns (uint256 a) {
            amountIn = a;
        } catch {
            return (address(0), address(0), 0, 0);
        }
        try vm.envUint("INTEGRATION_AMOUNT_OUT") returns (uint256 a) {
            amountOut = a;
        } catch {
            return (address(0), address(0), 0, 0);
        }
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
}
