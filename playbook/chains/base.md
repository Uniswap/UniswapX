# Base (chainId 8453) — DutchV3 rollout research

OP-stack L2 by Coinbase. Native ETH, EIP-1559, 2s blocks, single sequencer.
Already a first-class UniswapX chain: **Priority orders are deployed and live**
(see §Existing UniswapX coverage). DutchV3 is **purely additive** — it slots in
alongside Priority via a new `REACTOR_ADDRESS_MAPPING[8453][OrderType.Dutch_V3]`
entry; no existing surface changes.

Status: 🟢 Ready to deploy — standard EVM, canonical Permit2 + Arachnid present,
no chain-specific corrections (no §1 audit cells flag non-standard).

---

## §0 Pre-integration questionnaire

| Question | Why it matters | Base answer |
|---|---|---|
| **chainId** | Used in every repo's enums, every cosigner signature, every reactor deploy | `8453` |
| **RPC + explorer URLs** | Needed for env vars and integ tests | `https://mainnet.base.org` / `https://basescan.org` |
| **Block time (target)** | Drives `BLOCK_TIME_MS_BY_CHAIN`, decay block-length math, status-polling cadence | **2000ms** (probed: 3 consecutive blocks Δt = 2s, 2s) |
| **Finality model** | Drives min confirmations for fills; reorg risk | OP-stack: ~12s soft (sequencer), ~7d to L1 hard. Reorg risk same as other UniswapX OP-stack chains (Optimism, Unichain) |
| **`block.number` semantics** | Decides whether `BlockNumberish.sol` needs a new branch | Standard EVM monotonic counter — no change |
| **`block.basefee` semantics** | Drives V3 reactor's `_updateWithGasAdjustment`; tells us whether to set `adjustmentPerGweiBaseFee = 0` | Real wei, EIP-1559 dynamic. Probed: ~5 Mwei (~0.005 gwei) at idle. **No factory tweak needed** |
| **`block.timestamp` semantics** | Deadline math safety | Standard Unix seconds |
| **Native gas token** | Decides whether orders can use the `NATIVE` sentinel `address(0)` | **ETH** (bridged from L1). `WRAPPED_NATIVE_CURRENCY[8453] = WETH 0x4200000000000000000000000000000000000006` (already wired in `universe`/sdk-core) |
| **`CALLVALUE` / `BALANCE` / `SELFBALANCE` opcodes** | Multiple reactor + sample-executor code paths read these | Standard — `payable` paths and native sweeps in sample executors work as-is |
| **State creation costs** | Affects filler cold-fill economics | Standard OP-stack pricing; no special handling |
| **Permit2 at canonical address?** | Reactor binds to a fixed Permit2 address | ✅ **PRESENT** at `0x000000000022d473030f116ddee9f6b43ac78ba3` (probed `eth_getCode`, 18306 chars of code) |
| **Sequencer / private mempool / pre-confs** | Affects RFQ exclusivity protection beyond the reactor's `ExclusivityLib` | Single Coinbase-operated sequencer, public mempool, no pre-confs — standard `ExclusivityLib` semantics suffice (same as Optimism / Arbitrum) |
| **EIP-1559 / typed tx support** | RPC compatibility for fillers | ✅ Full EIP-1559; basefee is real and dynamic |
| **Routing surfaces (UniversalRouter, etc.)** | Whether existing sample executors can be reused | UniversalRouter v2.0 + v2.1.1 supported (`supportedURVersions` in `universe/.../base.ts`); sample executors reusable as-is |

**Probe one-liner result** (`https://mainnet.base.org`, blocks 45654484–45654486):

```
45654484 1778098315 0x4c4b40
45654485 1778098317 0x4c4b40
45654486 1778098319 0x4c4b40
```

Confirms: monotonic block numbers (Δ=1), 2s block time (Δt=2s, 2s), basefee `0x4c4b40` = 5,000,000 wei (~0.005 gwei) — real wei, dynamic EIP-1559 (this is just the OP-stack idle floor). **Arachnid CREATE2 deployer** `0x4e59b44847b379578588920ca78fbf26c0b4956c` also probed PRESENT (140 chars of code) → standard CREATE2 deploy path works.

---

## §1 EVM compatibility audit

| Behavior | Standard EVM | Base | Action |
|---|---|---|---|
| `block.number` monotonic & contiguous | ✅ | ✅ standard | none |
| `block.basefee` real wei value | ✅ | ✅ real wei, EIP-1559 dynamic | none — leave `adjustmentPerGweiBaseFee` at default in factory |
| `block.timestamp` seconds since epoch, monotonic | ✅ | ✅ standard | none |
| `msg.value` reflects sent ETH | ✅ | ✅ standard | none |
| `address(this).balance` reflects ETH balance | ✅ | ✅ standard | none — sample executors' native sweep paths work |
| Permit2 deployed at canonical address | ✅ | ✅ verified via `eth_getCode` | none |
| EIP-1559 fields populated | ✅ | ✅ | none |

Every cell answers standard. No `BlockNumberish.sol` fork, no factory `adjustmentPerGweiBaseFee = 0` override, no API-boundary native-sentinel rejection, no sub-second retry floor. Base is the textbook "all standard" chain.

---

## Existing UniswapX coverage on Base — Priority is already live

Base already runs UniswapX Priority orders. From `sdks/uniswapx-sdk/src/constants.ts`:

| Mapping | Base entry |
|---|---|
| `PERMIT2_MAPPING[8453]` | `0x000000000022d473030f116ddee9f6b43ac78ba3` (via `constructSameAddressMap`, `ChainId.BASE` is in `NETWORKS_WITH_SAME_ADDRESS`) |
| `UNISWAPX_ORDER_QUOTER_MAPPING[8453]` | `0xc6ef4C96Ee89e48Eff1C35545DBEED4Ad8dAC9D4` |
| `EXCLUSIVE_FILLER_VALIDATION_MAPPING[8453]` | `0x8A66A74e15544db9688B68B06E116f5d19e5dF90` (via same-address map) |
| `REACTOR_ADDRESS_MAPPING[8453][OrderType.Priority]` | `0x000000001Ec5656dcdB24D90DFa42742738De729` (verified PRESENT via `eth_getCode`, 26274 chars) |
| `REACTOR_ADDRESS_MAPPING[8453][OrderType.Dutch_V3]` | **(absent — this rollout adds it)** |

Implication: the SDK + service plumbing for Base is already fully exercised end-to-end (parameterization-api, x-service, trading-api all support `chainId 8453`). The DutchV3 rollout reduces to:

1. Deploy `V3DutchOrderReactor` to Base via `script/DeployDutchV3.s.sol`.
2. Add **only** `[OrderType.Dutch_V3]: <reactor>` to `REACTOR_ADDRESS_MAPPING[8453]` — leave the existing `Priority` entry untouched. The reactor lookup in `OffChainUniswapXOrderValidator.validateReactorAddress` is per-`OrderType`, so the two coexist without cross-talk.
3. Add `V3_BLOCK_LENGTH_BY_CHAIN[8453] = 15` (= 30s wallclock / 2s blocks) in trading-api `src/lib/constants.ts`.
4. Add `V3_BLOCK_BUFFER` entry for Base in parameterization-api (default `4` is fine at 2s blocks; matches Optimism/Polygon).
5. Reuse the existing `BLOCK_TIME_MS_BY_CHAIN[8453]` and `AVERAGE_BLOCK_TIME(BASE)` entries (already 2000ms / 2s).

No `disable_uniswapx_base` flag work needed — Priority already flows through the existing UniswapX `disable_uniswapx` config; the same flag's per-chain semantics will gate V3 traffic at routing time.

---

## Deploy parameters

| Param | Value | Source |
|---|---|---|
| `chainId` | `8453` | — |
| `RPC` | `https://mainnet.base.org` (or QuickNode endpoint per `universe/.../base.ts`) | — |
| `FOUNDRY_REACTOR_OWNER` | `0x2bad8182c09f50c8318d769245bea52c32be46cd` | NEW_CHAIN.md §3.2 (same as Arbitrum One / Tempo unless governance overrides) |
| `Permit2` | `0x000000000022d473030f116ddee9f6b43ac78ba3` | canonical, verified |
| `V3_BLOCK_LENGTH` (trading-api) | **`15`** | 30s decay / 2s block ≈ 15 blocks (`V3_DEFAULT_DECAY_DURATION_SECS = 30`) |
| `V3_BLOCK_BUFFER` (parameterization-api) | `4` | default, matches comparable 2s chains |
| `adjustmentPerGweiBaseFee` (DutchV3OrderFactory) | leave default | Base basefee is real wei + dynamic |
| `MIN_RETRY_WAIT_SECONDS` floor | not needed | 2s ≥ 1s Step Functions Wait granularity |

**Deploy command:**

```bash
FOUNDRY_REACTOR_OWNER=0x2bad8182c09f50c8318d769245bea52c32be46cd \
forge script script/DeployDutchV3.s.sol \
    --rpc-url https://mainnet.base.org \
    --broadcast \
    --private-key $DEPLOYER_KEY
```

Verify on `https://basescan.org`. Record the V3 reactor + OrderQuoter (already deployed at `0xc6ef4C96Ee89e48Eff1C35545DBEED4Ad8dAC9D4`, can reuse) addresses.

---

## Notes

- **DutchV3 is additive on Base.** No existing Priority traffic, sample-executor, or trading-api code path changes. The two reactors share Permit2 and the OrderQuoter lens.
- All cross-repo enum/config entries for `ChainId.BASE` already exist in sdk-core, parameterization-api, x-service, and trading-api. The diff per repo is small and surgical — see NEW_CHAIN.md §3.3 step list for the V3-specific touches.
- Base is the lowest-risk DutchV3 rollout candidate after Tempo: standard EVM, canonical infrastructure, an existing UniswapX deployment to crib operational learnings from, mature filler ecosystem.
