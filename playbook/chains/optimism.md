# Optimism (chainId 10) — DutchV3 rollout research

OP-stack L2. Standard EVM bytecode behavior. Permit2 deployed at canonical address. EIP-1559 with an additional L1 data fee component charged to the sender (paid by the filler at fill time). Single sequencer (OP Labs) with no public mempool exposure for pre-confs — same trust model as Base / Unichain.

Status: **🟢 Ready to deploy** — fully standard EVM, basefee live and dynamic, Permit2 + Arachnid CREATE2 factory both present. No factory tweaks needed.

---

## §0. Pre-integration questionnaire

| Question | Optimism answer |
|---|---|
| **chainId** | `10` |
| **RPC + explorer URLs** | `https://mainnet.optimism.io` (public) / `https://optimistic.etherscan.io` |
| **Block time (target)** | ~2s (measured: 3 consecutive blocks at +2s deltas — 151249730→151249732 over 4s) |
| **Finality model** | OP-stack: ~2s soft (sequencer), ~3min L1 safe, ~7d challenge window for full economic finality. UniswapX fill confirmation tracks soft inclusion, same as other rollups. |
| **`block.number` semantics** | Standard EVM monotonic counter — no `BlockNumberish.sol` branch needed |
| **`block.basefee` semantics** | Real wei, dynamic EIP-1559 (measured: 322 wei in latest blocks). NOTE: **L2 execution basefee only** — does NOT include the L1 data fee component, which is charged separately to the filler's tx but not visible to contract logic. |
| **`block.timestamp` semantics** | Standard Unix seconds |
| **Native gas token** | ETH (bridged). `WRAPPED_NATIVE_CURRENCY` = WETH at `0x4200000000000000000000000000000000000006` |
| **`CALLVALUE`/`BALANCE`/`SELFBALANCE` opcodes** | Standard — all reactor + sample-executor native paths work as on Mainnet |
| **State creation costs** | Standard EVM (20K SSTORE for new slot); L1 calldata posting cost dominates filler economics, not state cost |
| **Permit2 at canonical address?** | ✅ Yes — `eth_getCode` at `0x000000000022D473030F116dDEE9F6B43aC78BA3` returns 18306-byte runtime |
| **Sequencer / private mempool / pre-confs** | Single sequencer (OP Labs), no private mempool, no native pre-confs. Sequencer ordering provides effective MEV protection comparable to Base. ExclusivityLib filler exclusivity sufficient. |
| **EIP-1559 / typed tx support** | ✅ Yes — `baseFeePerGas` populated, type-2 txs supported |
| **Routing surfaces (UniversalRouter, etc.)** | UniversalRouter v2.0 + v2.1.1 deployed; v4 supported. Existing sample executors (UniversalRouterExecutor, SwapRouter02Executor) reusable as-is. |

Probe one-liner used:
```bash
RPC=https://mainnet.optimism.io
curl -s -X POST $RPC -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"eth_getCode","params":["0x000000000022D473030F116dDEE9F6B43aC78BA3","latest"],"id":1}'
```

Arachnid CREATE2 factory at `0x4e59b44847b379578588920cA78FbF26c0B4956C`: ✅ deployed (140-byte runtime).

---

## §1. EVM compatibility audit

| Behavior | Optimism | UniswapX impact |
|---|---|---|
| `block.number` monotonic & contiguous | ✅ standard | None |
| `block.basefee` real wei value | ✅ standard, dynamic (322 wei observed) | None — leave `adjustmentPerGweiBaseFee` at default. Note: this reflects L2 execution fee only, not the dominant L1 data fee. See "L1 data fee" note below. |
| `block.timestamp` seconds since epoch, monotonic | ✅ standard | None |
| `msg.value` (`CALLVALUE`) reflects sent ETH | ✅ standard | None — native paths fully functional |
| `address(this).balance` (`BALANCE`/`SELFBALANCE`) reflects ETH | ✅ standard | None — native sweeps in sample executors work |
| Permit2 at canonical address | ✅ Yes | None — reactor binds to canonical `0x0000…7BA3` |
| EIP-1559 fields populated | ✅ Yes | Cosigner can read `baseFeePerGas` normally |

No action items. Optimism is the closest thing to "default Mainnet" of any new chain in this rollout — it was one of the original OP-stack reference implementations and adheres to standard EVM semantics by design.

---

## Existing UniswapX coverage on Optimism

From `sdks/uniswapx-sdk/src/constants.ts`:

| Mapping | Entry for chainId 10 |
|---|---|
| `PERMIT2_MAPPING` | ❌ **missing** — needs to be added (will resolve to canonical `0x0000…7BA3`) |
| `UNISWAPX_ORDER_QUOTER_MAPPING` | ✅ `0xc6ef4C96Ee89e48Eff1C35545DBEED4Ad8dAC9D4` (shared with Mainnet/Base/Unichain/Arbitrum) |
| `REACTOR_ADDRESS_MAPPING` | ❌ **no entry** — Optimism is not in `NETWORKS_WITH_SAME_ADDRESS`, so neither legacy Dutch nor V2/V3 reactors are registered |
| `EXCLUSIVE_FILLER_VALIDATION_MAPPING` | inherited via `constructSameAddressMap` default → `0x8A66A74e15544db9688B68B06E116f5d19e5dF90` (verify deployed before relying on it; if not, set to zero address like Arbitrum) |

So **DutchV3 is a greenfield deploy on Optimism** — no prior reactor on the chain, OrderQuoter already in place to reuse. The SDK changes are: (a) add chainId 10 to `PERMIT2_MAPPING` (cleanest via adding `OPTIMISM` to `NETWORKS_WITH_SAME_ADDRESS`, which also picks up `EXCLUSIVE_FILLER_VALIDATION_MAPPING`), and (b) add a new `10: { [OrderType.Dutch_V3]: <reactor> }` entry to `REACTOR_ADDRESS_MAPPING`.

---

## Recommended deploy parameters

| Parameter | Value | Rationale |
|---|---|---|
| `FOUNDRY_REACTOR_OWNER` | `0x2bad8182c09f50c8318d769245bea52c32be46cd` | Same protocolFeeOwner as Arbitrum One — default unless governance dictates otherwise |
| `adjustmentPerGweiBaseFee` (in `DutchV3OrderFactory`) | **default** (non-zero) | Basefee is real, dynamic wei. Standard V3 gas-adjustment math applies for L2 execution costs. |
| `V3_BLOCK_LENGTH_BY_CHAIN[10]` | **15** (= ceil(30s / 2s) at `V3_DEFAULT_DECAY_DURATION_SECS = 30`) | Wallclock-equivalent decay window |
| `V3_BLOCK_BUFFER` (parameterization-api) | **4** (default) | 2s blocks — no need for the Tempo-style `1` override |
| `BLOCK_TIME_MS_BY_CHAIN[10]` (x-service) | `2000` | Matches measured cadence and `optimism.ts` `blockTimeMs` |
| `MIN_RETRY_WAIT_SECONDS_<CHAIN>` floor | **not needed** | Block time ≥ 1s, so Step Functions Wait state granularity is fine |
| `GAS_COMPARISON_MULTIPLIER_BY_CHAIN[10]` (trading-api) | `1.0` (default) | Gas is real and meaningful on Optimism — standard `compareQuotes` behavior |
| `WRAPPED_NATIVE_CURRENCY[10]` | `0x4200000000000000000000000000000000000006` (WETH) | Native is ETH; standard treatment |
| Native sentinel (`address(0)`) at trading-api boundary | **allow** | Has a real native token, unlike Tempo |

---

## Notes

**L1 data fee — important for filler gas accounting, not for the reactor.**
On OP-stack chains the *true* cost of fill txs is dominated by the L1 calldata-posting fee, which:

- is computed at tx submission time from the compressed serialized tx, not from `block.basefee`,
- is **not** observable from inside the contract (no opcode for it),
- scales with L1 ETH gas price, which is independent of `block.basefee` on Optimism.

The V3 gas-adjustment in `DutchV3OrderFactory` only models L2 execution gas. Fillers on Optimism must price L1 fee into their RFQ quote independently — this is the same model as Base / Unichain and is already what PMMs do today on those chains. No reactor or trading-api change is needed; just confirm the launch fillers are pricing L1 fee correctly during canary.

**Sequencer trust.** OP Labs runs the sole sequencer. UniswapX's exclusivity already protects winning fillers within an order; sequencer reordering risk is at parity with Base. No additional mitigation required beyond the existing `ExclusivityLib`.

**Finality.** Soft confirmation at sequencer inclusion (~2s) is what UniswapX status-polling tracks. The 7-day challenge window is irrelevant for fill confirmation purposes — bridges care about it; settlement does not.

**No `BlockNumberish.sol` branch.** Unlike Arbitrum (which uses `ArbSys` to expose the L1-anchored block number), Optimism's `block.number` is the L2 block number and is monotonic and contiguous. The default branch in `BlockNumberish.sol` is correct.
