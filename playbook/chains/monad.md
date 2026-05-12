# Monad (chainId 143) — DutchV3 rollout research

**Status:** 🟡 Greenfield UniswapX integration. Permit2 + Arachnid CREATE2 factory present at canonical addresses; no existing reactor / quoter / Permit2 / exclusivity entries for 143 in `uniswapx-sdk`. Standard EVM opcode behavior, but sub-second blocks pull in the same Step Functions retry-floor concern that bit Tempo.

**RPC probed:** `https://rpc.monad.xyz` (universe canonical RPC is `getQuicknodeEndpointUrl(UniverseChainId.Monad)`; the public endpoint is sufficient for §0 + §1 probes). Universe config: `/Users/cody.born/repos/universe/packages/uniswap/src/features/chains/evm/info/monad.ts` (`blockTimeMs: 500`, `tradingApiPollingIntervalMs: 150`, native `MON`, WMON `0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A`).

## Existing UniswapX coverage on chainId 143

From `sdks/uniswapx-sdk/src/constants.ts`:

| Mapping | Entry for 143 |
|---|---|
| `PERMIT2_MAPPING` | **absent** — Monad is not in `NETWORKS_WITH_SAME_ADDRESS` and has no explicit entry |
| `UNISWAPX_ORDER_QUOTER_MAPPING` | **absent** |
| `REACTOR_ADDRESS_MAPPING[143]` | **absent** (no Dutch / Dutch_V2 / Dutch_V3 / Priority / Relay / Hybrid) |
| `EXCLUSIVE_FILLER_VALIDATION_MAPPING` | **absent** |
| `UNISWAPX_V4_ORDER_QUOTER_MAPPING` | **absent** |
| `UNISWAPX_V4_TOKEN_TRANSFER_HOOK_MAPPING` | **absent** |
| `HYBRID_RESOLVER_ADDRESS_MAPPING` | **absent** |

`@uniswap/sdk-core` already has `ChainId.MONAD = 143` (chains.ts:33) plus `MONAD_ADDRESSES` (addresses.ts:418) for v3/v4 router contracts, so the sdk-core gate is already cleared. UniswapX work is purely additive: greenfield reactor + quoter deploy, then new PERMIT2 / QUOTER / REACTOR / EXCLUSIVE_FILLER entries keyed on `143`.

## §0 Pre-integration questionnaire

| Question | Monad answer |
|---|---|
| **chainId** | `143` (probed: `eth_chainId → 0x8f`) |
| **RPC + explorer** | `https://rpc.monad.xyz` (public) / `https://monadvision.com/` (per universe `monad.ts`) |
| **Block time (target)** | **~380–500ms** — sampled 30 consecutive blocks (72877751→72877780): 11s span across 30 blocks = 0.38s avg, with 2–3 blocks sharing each timestamp second. Universe config asserts `blockTimeMs: 500`. Treat as **sub-second** |
| **Finality model** | MonadBFT (HotStuff-derived) deterministic consensus, sub-second single-slot finality; high-throughput parallel-execution EVM |
| **`block.number` semantics** | Standard EVM monotonic counter — probed strictly increasing across samples. **No `BlockNumberish.sol` branch needed** (unlike Arbitrum's `ArbSys` special-case) |
| **`block.basefee` semantics** | Probed `baseFeePerGas = 0x174876e800` = 100 gwei (1e11 wei) **constant across all 30 sampled blocks**. Real wei units, not Tempo-style attodollars — but constant and EIP-1559-floored at the Monad protocol minimum. Treat as **non-dynamic**: set `adjustmentPerGweiBaseFee = 0` for 143 (the `_updateWithGasAdjustment` path has nothing to track) |
| **`block.timestamp` semantics** | Standard Unix seconds, monotonically non-decreasing. **Multiple blocks share a single timestamp second** (2–3/sec observed) — deadline math still safe (deadlines are seconds-granularity), but ordering between same-second blocks must use `block.number`, not `block.timestamp` |
| **Native gas token** | **MON** — universe config: `nativeCurrency.symbol = 'MON'`, decimals 18, `address = DEFAULT_NATIVE_ADDRESS_LEGACY` (0xeee…). Wrapped: `WMON 0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A`. NATIVE sentinel `address(0)` IS supported (unlike Tempo's stablecoin-only model) |
| **`CALLVALUE` / `BALANCE` / `SELFBALANCE` opcodes** | **Standard.** `eth_getBalance` for the zero address returned `0x171dadb3094041600272` (real wei); Permit2 balance returned `0x0`. `payable` modifiers, leftover-balance refund branches, and sample-executor native sweeps all work normally — no Tempo-style stubbing |
| **State creation costs** | Standard EVM gas schedule (no documented Tempo-style 12.5× multiplier). Parallel execution affects throughput, not per-tx pricing |
| **Permit2 at canonical address?** | ✅ Yes — `eth_getCode 0x000000000022D473030F116dDEE9F6B43aC78BA3` returned 18 306-byte runtime, identical length to mainnet/Tempo/Unichain |
| **Arachnid CREATE2 factory?** | ✅ Yes — `eth_getCode 0x4e59b44847b379578588920cA78FbF26c0B4956C` returned 140-byte runtime; deterministic vanity reactor addresses available |
| **Sequencer / private mempool / pre-confs** | Single MonadBFT consensus, public mempool, no separately-exposed pre-confs distinct from leader-elected fast finality. RFQ exclusivity via `ExclusivityLib` works unchanged |
| **EIP-1559 / typed tx support** | ✅ Type-2 transactions supported; `baseFeePerGas` field populated on every block. The cosigner can read it as a **sanity tripwire** but cannot use it for adjustment math (it's pinned at 100 gwei) |
| **Routing surfaces** | UniversalRouter v2.0 + v2.1.1 supported (`MONAD_CHAIN_INFO.supportedURVersions`); v4 supported (`supportsV4: true`). Existing `UniversalRouterExecutor`, `SwapRouter02Executor`, `MultiFillerSwapRouter02Executor` sample executors usable without modification |

## §1 EVM compatibility audit

| Behavior | Monad | Action |
|---|---|---|
| `block.number` monotonic & contiguous | ✅ standard | none |
| `block.basefee` real wei, dynamic | ⚠️ real wei but **constant 100 gwei** (no EIP-1559 dynamics observed across 30 blocks) | **Set `adjustmentPerGweiBaseFee = 0` in `DutchV3OrderFactory` for 143** (same lever as Tempo, different reason: Tempo was non-wei units; Monad is wei but pinned). Keep `startingBaseFee` populated for forward compatibility if Monad activates dynamic basefee later |
| `block.timestamp` Unix seconds, monotonic | ✅ but **non-strictly-monotonic at the second** (2–3 blocks/sec) | none — deadline math is second-granularity and safe; never assume same-second blocks are simultaneous (use `block.number`) |
| `msg.value` reflects sent ETH | ✅ standard (native MON) | none — orders may use NATIVE sentinel `0x0` |
| `address(this).balance` / `SELFBALANCE` reflects native balance | ✅ standard | none — sample-executor native sweeps are valid |
| Permit2 at canonical address | ✅ | add `143: "0x000000000022d473030f116ddee9f6b43ac78ba3"` to `PERMIT2_MAPPING` (or include 143 in `NETWORKS_WITH_SAME_ADDRESS`) |
| EIP-1559 fields populated | ✅ but pinned | cosigner reads `baseFeePerGas` as tripwire; does not drive adjustment |

## Deploy parameters

- **`FOUNDRY_REACTOR_OWNER`**: `0x2bad8182c09f50c8318d769245bea52c32be46cd` (Arbitrum One protocolFeeOwner; reuse unless governance specifies otherwise for Monad).
- **OrderQuoter**: deploy fresh on Monad — no shared deployment exists at chainId 143. If Arachnid CREATE2 vanity is desired, the canonical UniswapX OrderQuoter address (`0xc6ef4C96Ee89e48Eff1C35545DBEED4Ad8dAC9D4`, used on 1/10/8453/130/42161) can be replicated with the same salt + bytecode.
- **`V3_BLOCK_LENGTH_BY_CHAIN[143]`**: `ceil(30 / 0.5) = 60` blocks (30s wallclock decay at 500ms blocks). If the live block time is closer to 380ms, this is 30/0.38 ≈ 79; pick 60 to match the Tempo precedent (also 0.5s blocks → 60) and re-tune after canary measurement.
- **`V3_BLOCK_BUFFER` (parameterization-api)**: `1` (mirror Tempo — fast blocks; default `4` would over-buffer by ~2s).
- **`BLOCK_TIME_MS_BY_CHAIN[143]` (x-service)**: `500`.
- **`AVERAGE_BLOCK_TIME(143)` (x-service)**: `0.5` second — but see retry-floor note below.
- **`MIN_RETRY_WAIT_SECONDS_MONAD`**: **required.** Set to `2` (mirror Tempo). Step Functions Wait granularity is whole seconds; `0.5s` rounds to `0` → hot loop. Apply chain-scoped, not global (Correction D in NEW_CHAIN.md §4).
- **`PRIORITY_ORDER_TARGET_BLOCK_BUFFER[143]`**: `0` with comment — no Priority reactor planned for 143; `OffChainUniswapXOrderValidator.validateReactorAddress` rejects the path because no Priority entry will exist in `REACTOR_ADDRESS_MAPPING[143]`.
- **`HYBRID_ORDER_TARGET_BLOCK_BUFFER[143]`**: `0` with same comment — no Hybrid reactor planned.
- **`GAS_COMPARISON_MULTIPLIER_BY_CHAIN[143]` (trading-api)**: `0` — basefee is pinned at 100 gwei and parallel execution makes per-tx gas even less price-sensitive than typical L1s; suppress the gas-adjustment term in `compareQuotes` like Tempo. (Revisit if Monad turns on EIP-1559 dynamics.)
- **Trading-api `CHAIN_INFO_MAP[143]`**: `blockTimeMs: 500`, `pollingIntervalMs: 150` (matches universe `tradingApiPollingIntervalMs`), tune `orderTypeOverrides[OrderType.DUTCH_V3].deadlineBufferSecs` like Tempo (sub-second-block precedent) rather than Arbitrum.
- **`WRAPPED_NATIVE_CURRENCY[143]`**: `0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A` (WMON). Standard treatment — Monad has a native, so do **not** apply the Tempo native-rejection branch; do **not** apply Correction E.
- **uniswapx-sdk new entries** (chainId 143):
  - `PERMIT2_MAPPING[143] = "0x000000000022d473030f116ddee9f6b43ac78ba3"`
  - `UNISWAPX_ORDER_QUOTER_MAPPING[143] = <newly deployed quoter>`
  - `REACTOR_ADDRESS_MAPPING[143] = { [OrderType.Dutch_V3]: <newly deployed reactor> }`
  - `EXCLUSIVE_FILLER_VALIDATION_MAPPING[143] = "0x8A66A74e15544db9688B68B06E116f5d19e5dF90"` (canonical) **or** `"0x0000000000000000000000000000000000000000"` to disable on-chain exclusivity validation if no exclusivity contract is deployed at canonical on Monad — verify with `eth_getCode` before launch.

## Notes

- **Sub-second blocks parallel Tempo (TRA2-12).** Same retry-floor concern: Step Functions Wait state granularity is whole seconds, so `calculateDutchRetryWaitSeconds` for 143 must respect `MIN_RETRY_WAIT_SECONDS_MONAD = 2`, applied chain-scoped per Correction D. Do **not** widen the global floor — that tightens Arbitrum/Unichain unnecessarily. Same `V3_BLOCK_LENGTH = 60` precedent (30s wallclock at 500ms blocks).
- **Constant basefee parallels Tempo**, but for a different reason. Tempo's `2e10` is **attodollars/gas (non-wei)**; Monad's 100 gwei is **real wei but pinned by protocol minimum**. Both render `_updateWithGasAdjustment` a no-op, so both want `adjustmentPerGweiBaseFee = 0` (the swapper-signed lever per Correction B) and `GAS_COMPARISON_MULTIPLIER_BY_CHAIN = 0`. Document in `x-contracts/README.md` under a "Monad deployment notes" section so future readers understand it is wei-denominated and may become dynamic in a future Monad upgrade.
- **Native MON behaves normally** — unlike Tempo, do not propagate the API-boundary native-sentinel rejection (no Correction E). `CALLVALUE` / `BALANCE` / `SELFBALANCE` all return real values; the reactor's `payable` modifiers and leftover-balance refund branch are live, and sample executors' native sweeps work as on Ethereum mainnet.
- **Multi-block-per-second timestamps** are an EVM-spec-compliant edge case (timestamp must be non-decreasing, not strictly increasing). Any UniswapX code that orders events by `(blockNumber, txIndex)` is fine; any code keyed on `block.timestamp` for sub-second ordering would break. Audit `x-service`'s order-status polling and `check-order-status/util.ts` to confirm we always use `blockNumber` for ordering, never `timestamp`.
- **Parallel execution** is a throughput property and does not change UniswapX semantics: reactor calls are still sequenced inside a block, Permit2 signature replay protection still works, exclusivity windows still gate on `block.number`.
- **No `BlockNumberish.sol` fork needed** — Monad's `block.number` is a standard monotonic EVM counter; the Arbitrum `ArbSys` branch is irrelevant.
- **Dashboards**: chainId 143 is greenfield in x-service. Add chain-specific cuts during Phase 4 canary; reuse the Tempo dashboard panels as the template (sub-second-block chain class).
- **Feature flag**: gate behind `disable_uniswapx_monad` (default ON) in the config-service registry; flip to `{"threshold": 0}` at Phase 4 canary launch.
