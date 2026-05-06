# Zora (chainId 7777777) — DutchV3 rollout research

OP-stack L2 operated by the Zora team, focused on NFT/creator tooling. Standard EVM bytecode, native ETH bridged from Mainnet, EIP-1559 with the usual OP-stack L1 data fee component on top of the L2 execution basefee. Permit2 and the Arachnid CREATE2 deployer are both present at canonical addresses. Block time measured at ~2s. **DEX volume on Zora is materially smaller than the other EVM chains in this rollout** — RFQ may have thin or no PMM coverage at launch.

Status: **🟢 Ready to deploy** — fully standard EVM, no factory tweaks needed. Demand-side caveat (PMM coverage) is the gating consideration, not technical.

---

## §0. Pre-integration questionnaire

| Question | Zora answer |
|---|---|
| **chainId** | `7777777` (`eth_chainId` returns `0x76adf1`) |
| **RPC + explorer URLs** | `https://rpc.zora.energy` (public) / `https://explorer.zora.energy` |
| **Block time (target)** | ~2s (measured: 3 consecutive blocks 45702269/70/71 at +2s deltas — wallclock 4s span) |
| **Finality model** | OP-stack: ~2s soft (sequencer), L1 safe via batch posting to Mainnet, ~7d challenge window for full economic finality. UniswapX fill confirmation tracks soft inclusion, same as Optimism / Base. |
| **`block.number` semantics** | Standard EVM monotonic counter — no `BlockNumberish.sol` branch needed |
| **`block.basefee` semantics** | Real wei, dynamic EIP-1559 (measured: 252 wei in latest blocks). NOTE: **L2 execution basefee only** — does NOT include the L1 data fee component, which is charged separately to the filler's tx and not visible to contract logic. |
| **`block.timestamp` semantics** | Standard Unix seconds |
| **Native gas token** | ETH (bridged via `https://bridge.zora.energy/`). `WRAPPED_NATIVE_CURRENCY` = WETH at `0x4200000000000000000000000000000000000006` (canonical OP-stack predeploy) |
| **`CALLVALUE`/`BALANCE`/`SELFBALANCE` opcodes** | Standard — all reactor + sample-executor native paths work as on Mainnet |
| **State creation costs** | Standard EVM (20K SSTORE for new slot); L1 calldata posting cost dominates filler economics, not state cost |
| **Permit2 at canonical address?** | ✅ Yes — `eth_getCode` at `0x000000000022D473030F116dDEE9F6B43aC78BA3` returns 9152-byte runtime (full Permit2) |
| **Sequencer / private mempool / pre-confs** | Single sequencer (Zora team / Conduit), no private mempool, no native pre-confs. Sequencer ordering provides effective MEV protection comparable to Base / Optimism. ExclusivityLib filler exclusivity sufficient. |
| **EIP-1559 / typed tx support** | ✅ Yes — `baseFeePerGas` populated, type-2 txs supported |
| **Routing surfaces (UniversalRouter, etc.)** | UniversalRouter v2.0 + v2.1.1 deployed (per `zora.ts`); v4 supported (`supportsV4: true`). Existing sample executors reusable as-is. |

Arachnid CREATE2 factory at `0x4e59b44847b379578588920cA78FbF26c0B4956C`: ✅ deployed (69-byte canonical runtime).

Probe one-liner used:
```bash
RPC=https://rpc.zora.energy
curl -s -X POST $RPC -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"eth_getCode","params":["0x000000000022D473030F116dDEE9F6B43aC78BA3","latest"],"id":1}'
```

---

## §1. EVM compatibility audit

| Behavior | Zora | UniswapX impact |
|---|---|---|
| `block.number` monotonic & contiguous | ✅ standard | None |
| `block.basefee` real wei value | ✅ standard, dynamic (252 wei observed) | None — leave `adjustmentPerGweiBaseFee` at default. Reflects L2 execution fee only, not the dominant L1 data fee. See "L1 data fee" note. |
| `block.timestamp` seconds since epoch, monotonic | ✅ standard | None |
| `msg.value` (`CALLVALUE`) reflects sent ETH | ✅ standard | None — native paths fully functional |
| `address(this).balance` (`BALANCE`/`SELFBALANCE`) reflects ETH | ✅ standard | None — native sweeps in sample executors work |
| Permit2 at canonical address | ✅ Yes | None — reactor binds to canonical `0x0000…7BA3` |
| EIP-1559 fields populated | ✅ Yes | Cosigner can read `baseFeePerGas` normally |

No action items. Zora behaves as a stock OP-stack L2.

---

## Existing UniswapX coverage on Zora

From `sdks/uniswapx-sdk/src/constants.ts`:

| Mapping | Entry for chainId 7777777 |
|---|---|
| `PERMIT2_MAPPING` | ❌ **missing** — needs to be added (will resolve to canonical `0x0000…7BA3`) |
| `UNISWAPX_ORDER_QUOTER_MAPPING` | ❌ **missing** — Zora not in `NETWORKS_WITH_SAME_ADDRESS`; quoter must be deployed and added explicitly |
| `REACTOR_ADDRESS_MAPPING` | ❌ **no entry** — greenfield deploy |
| `EXCLUSIVE_FILLER_VALIDATION_MAPPING` | inherited via `constructSameAddressMap` default → `0x8A66A74e15544db9688B68B06E116f5d19e5dF90` (verify deployed before relying on it; if not, set to zero address) |

So **DutchV3 is a greenfield deploy on Zora** — both reactor and OrderQuoter need to be deployed, and three SDK mappings (`PERMIT2_MAPPING`, `UNISWAPX_ORDER_QUOTER_MAPPING`, `REACTOR_ADDRESS_MAPPING`) need new entries.

---

## Recommended deploy parameters

| Parameter | Value | Rationale |
|---|---|---|
| `FOUNDRY_REACTOR_OWNER` | `0x2bad8182c09f50c8318d769245bea52c32be46cd` | Same protocolFeeOwner as Arbitrum One — default unless governance dictates otherwise |
| `adjustmentPerGweiBaseFee` (in `DutchV3OrderFactory`) | **default** (non-zero) | Basefee is real, dynamic wei. Standard V3 gas-adjustment math applies for L2 execution costs. |
| `V3_BLOCK_LENGTH_BY_CHAIN[7777777]` | **15** (= ceil(30s / 2s) at `V3_DEFAULT_DECAY_DURATION_SECS = 30`) | Wallclock-equivalent decay window |
| `V3_BLOCK_BUFFER` (parameterization-api) | **4** (default) | 2s blocks — no Tempo-style override needed |
| `BLOCK_TIME_MS_BY_CHAIN[7777777]` (x-service) | `2000` | Matches measured cadence and `zora.ts` `blockTimeMs: 2000` |
| `MIN_RETRY_WAIT_SECONDS_<CHAIN>` floor | **not needed** | Block time ≥ 1s, Step Functions Wait state granularity is fine |
| `GAS_COMPARISON_MULTIPLIER_BY_CHAIN[7777777]` (trading-api) | `1.0` (default) | Gas is real and meaningful — standard `compareQuotes` behavior |
| `WRAPPED_NATIVE_CURRENCY[7777777]` | `0x4200000000000000000000000000000000000006` (WETH) | Native is ETH; standard OP-stack treatment |
| Native sentinel (`address(0)`) at trading-api boundary | **allow** | Has a real native token (ETH), unlike Tempo |

---

## Notes

**RFQ / PMM coverage is the binding constraint, not the bytecode.** Zora's DEX volume is a small fraction of Optimism / Base / Mainnet — the chain's product focus is NFT mints and creator monetization, not general spot trading. Concretely this means: (a) launch fillers may decline to quote Zora at all, (b) RFQ hit-rate during canary is likely low, (c) `compareQuotes` will fall back to Classic (UniversalRouter) for most flow. Do **not** treat low RFQ volume as a bug during canary on Zora; confirm with launch fillers up front whether they intend to quote at all, and consider whether a Zora rollout makes sense before contracts are deployed. Reactor + quoter contracts are inert if no RFQ flow lands — there is no on-chain risk to deploying speculatively, just wasted parameterization-api / x-service / trading-api wiring effort if no PMM ever turns on.

**L1 data fee — important for filler gas accounting, not the reactor.** Same caveat as Optimism / Base: the dominant cost of fill txs on OP-stack chains is L1 calldata posting, not L2 execution gas. It is computed at tx submission time from the compressed serialized tx, is not observable from inside the contract, and scales with L1 ETH gas price independently of `block.basefee`. The V3 gas-adjustment in `DutchV3OrderFactory` only models L2 execution gas; fillers must price L1 fee into RFQ quotes themselves. No reactor or trading-api change needed.

**Sequencer trust.** The Zora sequencer is operated by Conduit on behalf of the Zora team. Single-sequencer trust model at parity with Base / Optimism. UniswapX's `ExclusivityLib` already protects winning fillers; no additional mitigation required.

**Finality.** Soft confirmation at sequencer inclusion (~2s) is what UniswapX status-polling tracks. The 7-day challenge window matters for L1 bridges, not for fill confirmation.

**No `BlockNumberish.sol` branch.** Zora's `block.number` is the L2 block number — monotonic and contiguous, identical semantics to Optimism / Base. Default branch is correct.
