# Blast (chainId 81457) — DutchV3 rollout research

**Status:** 🟡 Ready to deploy DutchV3 with caveats — Permit2 + Arachnid CREATE2 factory both present, block time 2s, standard OP-stack-like EVM, BUT **native ETH and USDB are rebasing tokens**; reactor `balanceOf` accounting needs an explicit audit (see Notes).

**RPC probed:** `https://rpc.blast.io` (universe `RPCType.Default`).
QuickNode endpoint `getQuicknodeEndpointUrl(UniverseChainId.Blast)` is the universe Public/Interface RPC; the public endpoint suffices for §0 + §1 probes.

## Existing UniswapX coverage on chainId 81457

From `sdks/uniswapx-sdk/src/constants.ts`:

| Mapping | Entry for 81457 |
|---|---|
| `PERMIT2_MAPPING` | **absent** — Blast is not in `NETWORKS_WITH_SAME_ADDRESS` and has no explicit override. Must be added (Permit2 itself is deployed at the canonical address — verified below). |
| `UNISWAPX_ORDER_QUOTER_MAPPING` | **absent** — must deploy + add. |
| `REACTOR_ADDRESS_MAPPING[81457]` | **absent** — no Dutch / Dutch_V2 / Priority / Relay / V3 entries. Greenfield. |
| `EXCLUSIVE_FILLER_VALIDATION_MAPPING` | **absent** — Blast not in `NETWORKS_WITH_SAME_ADDRESS`; need explicit entry (canonical `0x8A66A74e15544db9688B68B06E116f5d19e5dF90` if deployed there, else add as `0x0`). |
| `UNISWAPX_V4_ORDER_QUOTER_MAPPING` | inherits the `0x0` default — fine, no V4 planned. |
| `UNISWAPX_V4_TOKEN_TRANSFER_HOOK_MAPPING` | inherits `0x0` default. |
| `HYBRID_RESOLVER_ADDRESS_MAPPING` | absent (Sepolia 1301 only). |

**No prior UniswapX surface on Blast.** This is a true greenfield rollout — every SDK mapping needs a fresh entry, and there is no existing Priority/V2 reactor flow to coexist with.

## §0 Pre-integration questionnaire

| Question | Blast answer |
|---|---|
| **chainId** | `81457` (probed `eth_chainId` → `0x13e31`) |
| **RPC + explorer** | `https://rpc.blast.io` (public) / `https://blastscan.io` (`apiURL: https://api.blastscan.io`) |
| **Block time (target)** | **~2s** — three consecutive blocks 34644267 → 34644269 spanned timestamps 1778098349 → 1778098353 (Δ = 2s/block). Matches universe `BLAST_CHAIN_INFO.blockTimeMs = 2000`. |
| **Finality model** | OP-stack L2; sequencer soft-confirmations seconds, L1 finality after batcher submits to Ethereum (~15min). |
| **`block.number` semantics** | Standard EVM monotonic counter (OP-stack). No `BlockNumberish.sol` branch needed. |
| **`block.basefee` semantics** | EIP-1559 wei, but **effectively pinned at the floor** — sampled `baseFeePerGas` at heads 34634269..34644269 was a flat `0xfc` (252 wei = 0.000000252 gwei); 1M blocks earlier was `0x106` (262 wei). Real wei units, dynamic on paper, but near-constant in practice. **Recommend setting `adjustmentPerGweiBaseFee = 0`** in `DutchV3OrderFactory[81457]`: the gas-adjustment lever has no signal at this floor. |
| **`block.timestamp` semantics** | Standard Unix seconds, monotonic (probed deltas +2s). |
| **Native gas token** | ETH (`BLAST_CHAIN_INFO.nativeCurrency.symbol = 'ETH'`). NATIVE sentinel `0x0` is supported on the surface — but ETH on Blast is **rebasing** unless contracts opt out. See Notes. |
| **`CALLVALUE` / `BALANCE` / `SELFBALANCE` opcodes** | Standard OP-stack EVM. `payable` modifiers, leftover-ETH refund branches in `BaseReactor`, and sample-executor native sweeps all execute as on mainnet — but the **balances they read may include rebase yield accrued mid-tx** (see Notes). |
| **State creation costs** | Standard OP-stack gas schedule; no Tempo-style multiplier. |
| **Permit2 at canonical address?** | ✅ Yes — `eth_getCode 0x000000000022D473030F116dDEE9F6B43aC78BA3` returned 9152-byte runtime (matches canonical Permit2 bytecode size). |
| **Arachnid CREATE2 factory?** | ✅ Yes — `eth_getCode 0x4e59b44847b379578588920cA78FbF26c0B4956C` returned canonical 69-byte deployer runtime. Deterministic vanity addresses available. |
| **Sequencer / private mempool / pre-confs** | Single Blast sequencer, public mempool, no formal pre-confs. RFQ `ExclusivityLib` works as on Base/Optimism. |
| **EIP-1559 / typed tx support** | ✅ Yes — `baseFeePerGas` populated. (Cosigner `startingBaseFee` tripwire near-useless here because basefee is pinned to floor; treat as informational.) |
| **Routing surfaces** | UniversalRouter v2.0 + v2.1.1 supported (`BLAST_CHAIN_INFO.supportedURVersions`); `supportsV4: true`. Existing `UniversalRouterExecutor` and `SwapRouter02Executor` are usable subject to the rebasing-token caveat (see Notes). |

## §1 EVM compatibility audit

| Behavior | Blast | Action |
|---|---|---|
| `block.number` monotonic & contiguous | ✅ | none |
| `block.basefee` real wei | ✅ wei-denominated, but pinned ≈252 wei | **set `adjustmentPerGweiBaseFee = 0` in `DutchV3OrderFactory[81457]`** — Tempo precedent (Correction B): gas-adjustment math gives no signal at a floor basefee, and you don't want filler gas economics tied to a near-constant. |
| `block.timestamp` Unix seconds, monotonic | ✅ | none |
| `msg.value` reflects sent ETH | ✅ | NATIVE sentinel works structurally, but see Notes — fillers / sample executors holding ETH across calls accrue rebase yield. |
| `address(this).balance` reflects ETH balance | ✅ | works, but is **non-monotonic upward** for contracts that haven't opted out of native rebase. See Notes. |
| ERC20 `balanceOf` is monotone w.r.t. transfers only | ❌ for **WETH (`0x4300...0004`)** and **USDB (`0x4300...0003`)** | **Audit the V3 reactor's `CurrencyLibrary.balanceOf` reads** before launch. See Notes — this is the Blast-specific risk. |
| Permit2 at canonical address | ✅ | add `81457: "0x000000000022d473030f116ddee9f6b43ac78ba3"` to `PERMIT2_MAPPING`. |
| EIP-1559 fields populated | ✅ | cosigner can read `baseFeePerGas` but treat as floor-pinned. |

**Action items flagged for x-contracts/README.md "Blast deployment notes":**
1. `adjustmentPerGweiBaseFee = 0` in trading-api `DutchV3OrderFactory` for chainId 81457 (Correction B; basefee pinned at floor).
2. **Rebasing-token audit** for `V3DutchOrderReactor` — confirm whether the resolved-output settlement path or any `balanceOf(address(this))` invariant assumes monotone-by-transfer behavior. WETH and USDB on Blast violate this. UniswapX flow time is ~seconds so per-fill drift is sub-wei, but invariants like "post-fill balance == pre-fill balance + amountOut" can break on a strict-equality check.
3. Document filler-side guidance: any sample executor that opts into ETH/USDB **rebasing** mode and holds inventory across blocks will see balances drift; reconciliation should use transfer events, not `balanceOf` snapshots.

## Deploy parameters

- **`FOUNDRY_REACTOR_OWNER`**: `0x2bad8182c09f50c8318d769245bea52c32be46cd` (Arbitrum One protocolFeeOwner; reuse unless governance specifies otherwise).
- **OrderQuoter**: deploy fresh (no prior entry in `UNISWAPX_ORDER_QUOTER_MAPPING[81457]`); use Arachnid CREATE2 factory for vanity address parity with `0xc6ef4C96Ee89e48Eff1C35545DBEED4Ad8dAC9D4` if desired (factory present, verified above).
- **`V3_BLOCK_LENGTH_BY_CHAIN[81457]`**: `ceil(30 / 2) = 15` blocks (30s wallclock decay at 2s blocks).
- **`V3_BLOCK_BUFFER` (parameterization-api)**: `4` (default — 2s blocks are not sub-second, no special tuning required).
- **`BLOCK_TIME_MS_BY_CHAIN[81457]` (x-service)**: `2000` (matches universe).
- **`AVERAGE_BLOCK_TIME(81457)` (x-service)**: `2` seconds.
- **`MIN_RETRY_WAIT_SECONDS_<CHAIN>`**: not needed — 2s ≥ Step Functions Wait granularity.
- **`PRIORITY_ORDER_TARGET_BLOCK_BUFFER[81457]`**: `0` with comment ("no Priority reactor on Blast; rejected upstream by `OffChainUniswapXOrderValidator.validateReactorAddress`").
- **`HYBRID_ORDER_TARGET_BLOCK_BUFFER[81457]`**: `0` with same comment.
- **`GAS_COMPARISON_MULTIPLIER_BY_CHAIN[81457]` (trading-api)**: `1.0` (basefee is real wei; even though near-floor, gas accounting is in standard units — unlike Tempo's attodollar denomination).
- **`adjustmentPerGweiBaseFee` (trading-api `DutchV3OrderFactory`)**: **`0`** for V3 inputs and outputs on chainId 81457 (basefee pinned at floor; Correction B).
- **Trading-api `CHAIN_INFO_MAP[81457]`**: `blockTimeMs: 2000`, `pollingIntervalMs: 200` (matches universe `tradingApiPollingIntervalMs`); tune `orderTypeOverrides[OrderType.DUTCH_V3].deadlineBufferSecs` similarly to Base (2s blocks, OP-stack).
- **`WRAPPED_NATIVE_CURRENCY[81457]`**: `0x4300000000000000000000000000000000000004` (Blast WETH) — **with the rebasing caveat documented at the binding site**, not silently.
- **`PERMIT2_MAPPING[81457]`**: `0x000000000022d473030f116ddee9f6b43ac78ba3` (verified deployed). Either add Blast to `NETWORKS_WITH_SAME_ADDRESS` (also adds it to `EXCLUSIVE_FILLER_VALIDATION_MAPPING` and `UNISWAPX_ORDER_QUOTER_MAPPING` defaults — undesirable since OrderQuoter at the canonical address is unlikely to exist there) **or** add an explicit `81457: <address>` entry. Prefer the explicit entry to avoid coupling.

## Notes

- **Blast rebasing tokens are the headline risk for this rollout.** Native ETH and native USDB on Blast auto-accrue yield by default; smart contracts must explicitly opt out (or in to "claimable" mode) via the `Blast` precompile. **WETH (`0x4300...0004`) and USDB (`0x4300...0003`) on Blast have non-standard `balanceOf` semantics: the returned balance increases over time without any explicit `Transfer` event.** Any contract holding either token observes upward balance drift between blocks.
- **Reactor accounting impact:** `CurrencyLibrary.balanceOf(token, address)` (in `x-contracts/src/lib/CurrencyLibrary.sol`) reads `IERC20(token).balanceOf(this)` for non-NATIVE tokens. If `V3DutchOrderReactor` ever asserts "post-fill balance == pre-fill balance + delta", or relies on transfer-only conservation, those invariants will be **off by the rebase yield accrued in the block(s) the reactor held the token**. UniswapX swap flows complete in seconds (often a single block), so per-fill drift is pico-units and economically irrelevant — but a strict-equality `require` will revert spuriously, and any subtraction-based accounting on long-held inventory drifts.
- **Action before mainnet launch:** audit `V3DutchOrderReactor.sol` and any sample executor that touches WETH/USDB on Blast for `balanceOf(this)` reads against held inventory. Convert any equality checks to range checks, or have the reactor `configure(YieldMode.VOID)` for native ETH and call `IERC20Rebasing.configure(YieldMode.VOID)` on WETH/USDB it ever holds. The OP-stack `BaseReactor` doesn't currently do either — it'll silently accumulate dust yield on any leftover balance, which is harmless but worth documenting.
- **Filler test plan (gating Phase 4 canary):** require launch fillers to run a soak test against rebasing flows on Blast testnet/mainnet — fill an order, hold the WETH or USDB output for 1, 10, and 60 blocks, and confirm their accounting reconciles. Fillers using transfer-event-based reconciliation are fine; fillers comparing `balanceOf` snapshots will see drift. **This is a hard prerequisite for going live**, not a nice-to-have. PMMs that have integrated on Base/Optimism may not have hit this class of token before.
- **Sample executors:** `UniversalRouterExecutor`, `SwapRouter02Executor`, and `MultiFillerSwapRouter02Executor` will work mechanically on Blast but inherit the same rebasing risk for any leftover WETH/USDB they sweep. Document this in `x-contracts/README.md` under "Blast deployment notes" alongside the basefee/factory notes.
- **Greenfield rollout** — every SDK mapping needs a new entry (Permit2, OrderQuoter, REACTOR, ExclusiveFillerValidation). No reactor-address collision risk and no reverse-mapping conflicts since 81457 is absent from `REACTOR_ADDRESS_MAPPING` today.
- **Feature flag:** gate behind a fresh `disable_uniswapx_blast` flag. Keep ON until rebasing soak test passes.
- **Dashboards** do not yet exist for chainId 81457; add chain-scoped cuts during Phase 3.
