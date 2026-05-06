# Linea (chainId 59144) — DutchV3 rollout research

ConsenSys-built **Type-2 zkEVM L2** with native ETH bridged from Ethereum mainnet. Linea aims for full EVM equivalence at the bytecode level — closer to standard EVM than zkSync Era (Type-4) and roughly on par with Scroll / Polygon zkEVM. Standard CREATE2 derivation, standard opcodes, EIP-1559. Public sequencer run by ConsenSys, no public mempool exposure for pre-confs.

Status: **🟢 Ready to deploy** — Permit2 + Arachnid CREATE2 factory both deployed at canonical addresses (verified via `eth_getCode`), confirming standard CREATE2 derivation. EVM-equivalence-class L2; no factory tweaks needed.

---

## §0. Pre-integration questionnaire

| Question | Linea answer |
|---|---|
| **chainId** | `59144` |
| **RPC + explorer URLs** | `https://rpc.linea.build` (public) / `https://lineascan.build` |
| **Block time (target)** | ~2s target (measured: 3 consecutive blocks at 30534244→30534246, deltas of +16s, +4s — sequencer cadence is variable but typically 2s under load; Linea docs and `linea.ts` `blockTimeMs: 2000` agree) |
| **Finality model** | Soft inclusion at sequencer (sub-block), L1 safe after batch submission (~hours), full proof finality after zk validity proof posts to L1 (~hours-to-days). UniswapX status-polling tracks soft inclusion, same as other rollups. |
| **`block.number` semantics** | Standard EVM monotonic counter — no `BlockNumberish.sol` branch needed. (Linea's Type-2 zkEVM equivalence covers this; unlike Arbitrum's `ArbSys` divergence.) |
| **`block.basefee` semantics** | Real wei, dynamic EIP-1559 (measured: 7 wei in latest blocks — Linea L2 basefee is typically very low single-digit wei, but it IS real wei and IS dynamic, not constant or attodollar-denominated like Tempo). |
| **`block.timestamp` semantics** | Standard Unix seconds |
| **Native gas token** | ETH (bridged from L1). `WRAPPED_NATIVE_CURRENCY` = WETH at `0xe5D7C2a44FfDDf6b295A15c148167daaAf5Cf34f` |
| **`CALLVALUE`/`BALANCE`/`SELFBALANCE` opcodes** | Standard — Linea's Type-2 zkEVM preserves these opcodes' standard semantics. All reactor + sample-executor native paths work as on Mainnet. |
| **State creation costs** | Standard EVM (20K SSTORE for new slot). Linea's prover cost model does not impose extra gas on contract storage at the EVM level. |
| **Permit2 at canonical address?** | ✅ Yes — `eth_getCode` at `0x000000000022D473030F116dDEE9F6B43aC78BA3` returns 18306-byte runtime |
| **Sequencer / private mempool / pre-confs** | Single sequencer (ConsenSys), no public mempool exposure, no native pre-confs. Sequencer ordering provides effective MEV protection comparable to Base / Optimism. ExclusivityLib is sufficient. |
| **EIP-1559 / typed tx support** | ✅ Yes — `baseFeePerGas` populated, type-2 txs supported |
| **Routing surfaces (UniversalRouter, etc.)** | UniversalRouter v2.0 + v2.1.1 deployed; v4 supported. Existing sample executors (UniversalRouterExecutor, SwapRouter02Executor) reusable as-is. |

Probe used:
```bash
RPC=https://rpc.linea.build
curl -s -X POST $RPC -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"eth_getCode","params":["0x000000000022D473030F116dDEE9F6B43aC78BA3","latest"],"id":1}'
# → 18306-byte Permit2 runtime
curl -s -X POST $RPC -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"eth_getCode","params":["0x4e59b44847b379578588920cA78FbF26c0B4956C","latest"],"id":1}'
# → 140-byte Arachnid CREATE2 deployer runtime
```

The presence of Permit2 (`0x000000000022D473…`) AND the Arachnid factory (`0x4e59b448…`) at their canonical addresses jointly **confirms Linea uses standard EVM CREATE2 derivation** (`keccak256(0xff ++ deployer ++ salt ++ keccak256(initCode))`), unlike zkSync Era which uses a divergent derivation and re-derives canonical-address contracts at non-canonical addresses (e.g. multicall3 on zkSync at `0xF9cda624…` per `uniswapx-sdk/src/constants.ts:154`). For Linea, all CREATE2-derived UniswapX deploys will land at the same addresses as on Mainnet/Base/Unichain — no per-chain address divergence.

---

## §1. EVM compatibility audit

| Behavior | Linea | UniswapX impact |
|---|---|---|
| `block.number` monotonic & contiguous | ✅ standard | None |
| `block.basefee` real wei value | ✅ standard, dynamic (7 wei observed; very low but real) | None — leave `adjustmentPerGweiBaseFee` at default. Gas-adjustment math is mathematically correct; with basefee in single-digit wei it just produces tiny adjustments, which is the right behavior. |
| `block.timestamp` seconds since epoch, monotonic | ✅ standard | None |
| `msg.value` (`CALLVALUE`) reflects sent ETH | ✅ standard | None — native paths fully functional |
| `address(this).balance` (`BALANCE`/`SELFBALANCE`) reflects ETH | ✅ standard | None — native sweeps in sample executors work |
| Permit2 at canonical address | ✅ Yes | None — reactor binds to canonical `0x0000…7BA3` |
| EIP-1559 fields populated | ✅ Yes | Cosigner can read `baseFeePerGas` normally |

No action items. Linea's Type-2 zkEVM aims for bytecode-level EVM equivalence; the audit is clean.

---

## Existing UniswapX coverage on Linea

From `sdks/uniswapx-sdk/src/constants.ts`:

| Mapping | Entry for chainId 59144 |
|---|---|
| `PERMIT2_MAPPING` | ❌ **missing** — needs to be added (will resolve to canonical `0x0000…7BA3`) |
| `UNISWAPX_ORDER_QUOTER_MAPPING` | ❌ **missing** — `NETWORKS_WITH_SAME_ADDRESS` only includes Mainnet/Goerli/Polygon/Base/Unichain; Linea is not covered. Will need a new entry post-deploy. |
| `REACTOR_ADDRESS_MAPPING` | ❌ **no entry** — Linea is not in `NETWORKS_WITH_SAME_ADDRESS`, so no reactors of any kind are registered |
| `EXCLUSIVE_FILLER_VALIDATION_MAPPING` | inherited via `constructSameAddressMap` default → `0x8A66A74e15544db9688B68B06E116f5d19e5dF90` (verify deployed before relying on it; if not, set to zero address as Arbitrum does) |

So **DutchV3 is a greenfield deploy on Linea** — nothing UniswapX exists on this chain today. SDK changes: (a) add chainId 59144 to `PERMIT2_MAPPING` (cleanest via adding `LINEA` to `NETWORKS_WITH_SAME_ADDRESS`, which also picks up `EXCLUSIVE_FILLER_VALIDATION_MAPPING`), (b) add the deployed OrderQuoter address to `UNISWAPX_ORDER_QUOTER_MAPPING`, and (c) add `59144: { [OrderType.Dutch_V3]: <reactor> }` to `REACTOR_ADDRESS_MAPPING`.

---

## Recommended deploy parameters

| Parameter | Value | Rationale |
|---|---|---|
| `FOUNDRY_REACTOR_OWNER` | `0x2bad8182c09f50c8318d769245bea52c32be46cd` | Same protocolFeeOwner as Arbitrum One — default unless governance dictates otherwise |
| `adjustmentPerGweiBaseFee` (in `DutchV3OrderFactory`) | **default** (non-zero) | Basefee is real, dynamic wei. Standard V3 gas-adjustment math applies. |
| `V3_BLOCK_LENGTH_BY_CHAIN[59144]` | **15** (= ceil(30s / 2s) at `V3_DEFAULT_DECAY_DURATION_SECS = 30`) | Wallclock-equivalent decay window |
| `V3_BLOCK_BUFFER` (parameterization-api) | **4** (default) | 2s blocks — no need for the Tempo-style `1` override |
| `BLOCK_TIME_MS_BY_CHAIN[59144]` (x-service) | `2000` | Matches `linea.ts` `blockTimeMs` and Linea's stated target |
| `MIN_RETRY_WAIT_SECONDS_<CHAIN>` floor | **not needed** | Block time ≥ 1s, so Step Functions Wait state granularity is fine |
| `GAS_COMPARISON_MULTIPLIER_BY_CHAIN[59144]` (trading-api) | `1.0` (default) | Gas is real and meaningful — standard `compareQuotes` behavior |
| `WRAPPED_NATIVE_CURRENCY[59144]` | `0xe5D7C2a44FfDDf6b295A15c148167daaAf5Cf34f` (WETH) | Native is bridged ETH; standard treatment |
| Native sentinel (`address(0)`) at trading-api boundary | **allow** | Has a real native token, unlike Tempo |

---

## Notes

**zkEVM lineage — but Type-2, not Type-4.** Linea is a zkEVM, which historically prompts caution. The two integration risks of zk-rollups for UniswapX are: (1) divergent CREATE2 address derivation (zkSync Era's biggest footgun), and (2) non-standard opcode semantics or gas accounting that breaks reactor assumptions. Linea is a **Type-2 zkEVM** targeting full bytecode EVM-equivalence — neither risk materializes:
- The Permit2 + Arachnid CREATE2 factory probes confirm canonical addresses are reachable, which is the strongest possible bytecode-level evidence that CREATE2 derivation matches mainnet.
- Type-2 preserves opcode semantics including `CALLVALUE`/`BALANCE`/`SELFBALANCE`/`block.basefee`/`block.number`. No reactor or sample-executor adaptation needed.

Practical conclusion: treat Linea like Optimism/Base for UniswapX integration purposes, **not** like zkSync. The "zkEVM" label is real but the integration surface is a standard EVM rollup.

**L1 data-fee accounting.** Like all rollups posting calldata to L1, the *true* fill cost includes an L1 data fee that:
- is computed at tx submission from the compressed tx,
- is **not** observable from inside the contract,
- scales with L1 ETH gas price independent of L2 `block.basefee`.

The V3 gas-adjustment in `DutchV3OrderFactory` only models L2 execution gas. Fillers must price L1 data-fee into RFQ quotes independently — same model as Optimism/Base/Unichain, already standard PMM practice. No reactor or trading-api change needed.

**Sequencer trust.** ConsenSys runs the sole sequencer. UniswapX exclusivity protects winning fillers within an order; sequencer-reorder risk is at parity with Base / Optimism. No additional mitigation required beyond the existing `ExclusivityLib`.

**Finality.** Soft confirmation at sequencer inclusion (~2s) is what UniswapX status-polling tracks. zk-proof finalization on L1 (hours-to-days) is irrelevant for fill confirmation purposes — bridges care about it; settlement does not.

**No `BlockNumberish.sol` branch.** Linea's `block.number` is the L2 block number, monotonic and contiguous. The default branch in `BlockNumberish.sol` is correct.
