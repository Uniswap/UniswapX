# Ethereum Mainnet (chainId 1) — DutchV3 rollout research

L1 PoS chain. Standard EVM bytecode behavior — every other UniswapX chain is a derivative of this one. Permit2 deployed at canonical address. EIP-1559 with real, dynamic basefee in wei. Public mempool, no sequencer. Dutch v1 + Dutch_V2 + Relay reactors are already live; **DutchV3 is the only missing piece.**

Status: **🟢 Ready to deploy** — fully standard EVM, basefee dynamic, Permit2 + Arachnid CREATE2 factory both present, OrderQuoter already deployed and shared. Pure additive deploy of a single V3 reactor.

---

## §0. Pre-integration questionnaire

| Question | Mainnet answer |
|---|---|
| **chainId** | `1` |
| **RPC + explorer URLs** | `https://ethereum-rpc.publicnode.com` (public; universe also lists Quicknode/Infura/Ankr/Blast/MEV-Blocker) / `https://etherscan.io` |
| **Block time (target)** | ~12s (measured: 25038301→25038302 +12s, 25038302→25038304 +24s over 2 blocks; matches universe `blockTimeMs: 12000`) |
| **Finality model** | PoS Casper FFG: ~13min (2 epochs × ~6.4min) for full economic finality. Soft inclusion at single-block confirmation; UniswapX fill polling tracks single-block inclusion same as today's V1/V2 flow. |
| **`block.number` semantics** | Standard EVM monotonic counter — no `BlockNumberish.sol` branch needed (this is the reference implementation) |
| **`block.basefee` semantics** | Real wei, dynamic EIP-1559 (measured: ~675–743 Mwei range in latest blocks). Standard. |
| **`block.timestamp` semantics** | Standard Unix seconds, monotonic, +12s per slot |
| **Native gas token** | ETH. `WRAPPED_NATIVE_CURRENCY` = WETH at `0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2` |
| **`CALLVALUE`/`BALANCE`/`SELFBALANCE` opcodes** | Standard — all reactor + sample-executor native paths work as designed |
| **State creation costs** | Standard EVM (20k SSTORE for new slot, 22.1k cold) — original baseline |
| **Permit2 at canonical address?** | ✅ Yes — `eth_getCode` at `0x000000000022D473030F116dDEE9F6B43aC78BA3` returns 18306-byte runtime |
| **Sequencer / private mempool / pre-confs** | None. Fully public mempool with proposer-builder separation (Flashbots/MEV-Boost). No native pre-confs. ExclusivityLib + cosigner exclusivity is the only filler protection — same as today's V1/V2 deploys on Mainnet. |
| **EIP-1559 / typed tx support** | ✅ Yes — type-2 + type-3 (blob) txs supported; `baseFeePerGas` populated |
| **Routing surfaces (UniversalRouter, etc.)** | UniversalRouter v2.0 + v2.1.1 deployed; v4 supported. All existing sample executors reusable as-is — Mainnet was the deploy target they were built against. |

Probe one-liners used:
```bash
RPC=https://ethereum-rpc.publicnode.com
cast code 0x000000000022D473030F116dDEE9F6B43aC78BA3 --rpc-url $RPC  # Permit2
cast code 0x4e59b44847b379578588920cA78FbF26c0B4956C --rpc-url $RPC  # Arachnid CREATE2
```

Arachnid CREATE2 factory: ✅ deployed.

---

## §1. EVM compatibility audit

| Behavior | Mainnet | UniswapX impact |
|---|---|---|
| `block.number` monotonic & contiguous | ✅ standard | None — reference implementation |
| `block.basefee` real wei value | ✅ standard, dynamic (~700 Mwei observed) | None — leave `adjustmentPerGweiBaseFee` at default |
| `block.timestamp` seconds since epoch, monotonic | ✅ standard | None |
| `msg.value` (`CALLVALUE`) reflects sent ETH | ✅ standard | None — native paths fully functional |
| `address(this).balance` (`BALANCE`/`SELFBALANCE`) reflects ETH | ✅ standard | None — native sweeps in sample executors work |
| Permit2 at canonical address | ✅ Yes | None — reactor binds to canonical `0x0000…7BA3` |
| EIP-1559 fields populated | ✅ Yes | Cosigner reads `baseFeePerGas` normally |

No action items. Mainnet is the canonical EVM behavior all other audits are graded against.

---

## Existing UniswapX coverage on Mainnet

From `sdks/uniswapx-sdk/src/constants.ts` (entry `1: { … }`):

| Mapping | Entry for chainId 1 |
|---|---|
| `PERMIT2_MAPPING` | ✅ canonical `0x000000000022D473030F116dDEE9F6B43aC78BA3` (via `constructSameAddressMap`) |
| `UNISWAPX_ORDER_QUOTER_MAPPING` | ✅ `0xc6ef4C96Ee89e48Eff1C35545DBEED4Ad8dAC9D4` |
| `REACTOR_ADDRESS_MAPPING` | ✅ `Dutch` `0x6000da47483062A0D734Ba3dc7576Ce6A0B645C4` · ✅ `Dutch_V2` `0x00000011F84B9aa48e5f8aA8B9897600006289Be` · ✅ `Relay` `0x0000000000A4e21E2597DCac987455c48b12edBF` · ❌ **`Dutch_V3` missing** · `Priority` placeholder zero |
| `EXCLUSIVE_FILLER_VALIDATION_MAPPING` | ✅ `0x8A66A74e15544db9688B68B06E116f5d19e5dF90` (via `constructSameAddressMap`) |

**DutchV3 is the only gap.** All surrounding infra (PERMIT2, OrderQuoter, exclusive-filler validator) is already wired and reused. SDK change is a one-line addition: `[OrderType.Dutch_V3]: <new reactor>` to the existing `1: { … }` block.

---

## Recommended deploy parameters

| Parameter | Value | Rationale |
|---|---|---|
| `FOUNDRY_REACTOR_OWNER` | `0x2bad8182c09f50c8318d769245bea52c32be46cd` | Same protocolFeeOwner as Arbitrum One / existing Mainnet V2 — default unless governance overrides |
| Salt-mining target | leading-zero pattern matching existing Mainnet reactors (e.g. `0x00000011…` for V2, `0x0000000000…` for Relay) | Cosmetic but consistent with prior deploys; cheap to mine via Arachnid CREATE2 |
| `adjustmentPerGweiBaseFee` (in `DutchV3OrderFactory`) | **default** (non-zero) | Real, dynamic wei basefee. Standard V3 gas-adjustment math applies. |
| `V3_BLOCK_LENGTH_BY_CHAIN[1]` | **3** (= ceil(30s / 12s) at `V3_DEFAULT_DECAY_DURATION_SECS = 30`) | Wallclock-equivalent 30s decay; only 3 blocks fit |
| `V3_BLOCK_BUFFER` (parameterization-api) | **4** (default) | 12s blocks — plenty of headroom, no override needed |
| `BLOCK_TIME_MS_BY_CHAIN[1]` (x-service) | `12000` | Matches measured cadence and `mainnet.ts` `blockTimeMs` |
| `MIN_RETRY_WAIT_SECONDS_<CHAIN>` floor | **not needed** | 12s blocks; Step Functions Wait granularity is fine |
| `GAS_COMPARISON_MULTIPLIER_BY_CHAIN[1]` (trading-api) | `1.0` (default) | Gas is meaningful and dominant — standard `compareQuotes` |
| `WRAPPED_NATIVE_CURRENCY[1]` | `0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2` (WETH) | Already populated; native sentinel `address(0)` allowed |
| Native sentinel (`address(0)`) at trading-api boundary | **allow** | Has real native ETH |

---

## Notes

**3-block decay window is tight.** With 12s blocks, a default 30s decay only spans 3 blocks (`ceil(30/12)=3`). This is the smallest decay block-length of any UniswapX chain. Confirm `V3_BLOCK_BUFFER = 4` doesn't push the decay end past `deadline` for typical orders; if so, either bump `V3_DEFAULT_DECAY_DURATION_SECS` for chain 1, or shrink the buffer. Worth a focused review during canary.

**Public mempool / MEV.** Unlike rollups with single sequencers, Mainnet has a fully public mempool. Cosigner-issued exclusivity windows + ExclusivityLib are the *only* filler protection on this chain. This is unchanged from today's Dutch v1/v2 behavior — V3 inherits it.

**Coexistence with V1/V2.** V2 reactor at `0x00000011F84B9aa48e5f8aA8B9897600006289Be` will continue to operate. Trading-api's `RFQQuoter` protocol-version mapping needs to advertise `UNISWAPX_V3` for Mainnet *in addition to* (or replacing) V2 — coordinate with PMMs on the cutover. No on-chain interaction; reactors are independent.

**No `BlockNumberish.sol` branch.** This is the canonical L1 implementation — `block.number` is the chain's native block number, monotonic and contiguous. Default branch is correct.

**Finality polling.** Existing x-service `AVERAGE_BLOCK_TIME(1) = 12s` and `OLDEST_BLOCK_BY_CHAIN[1]` entries already exist for V1/V2; verify they're current but no new wiring needed.
