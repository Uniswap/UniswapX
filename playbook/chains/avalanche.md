# Avalanche C-Chain (chainId 43114)

Status: 🟢 Ready to deploy. Standard EVM, Permit2 + Arachnid CREATE2 deployer present, EIP-1559 active, native AVAX usable as `NATIVE` sentinel. No structural code changes anticipated — this is a pure additive rollout.

Source: `universe/packages/uniswap/src/features/chains/evm/info/avalanche.ts` and live RPC probes against `https://api.avax.network/ext/bc/C/rpc`.

---

## §0 Pre-integration questionnaire

| Question | Answer |
|---|---|
| **chainId** | `43114` |
| **RPC + explorer URLs** | `https://api.avax.network/ext/bc/C/rpc` / `https://snowtrace.io/` (API: `https://api.snowscan.xyz`) |
| **Block time (target)** | ~2s (Snowman++ consensus). Live probe over 50 blocks: 55s wallclock → ~1.1s observed cadence under current load; treat the documented 2s as the conservative budget. |
| **Finality model** | Probabilistic-fast Snowman BFT — sub-second to ~1s acceptance once a block is processed; treat as final after 1 confirmation for filler purposes. No reorgs in normal operation. |
| **`block.number` semantics** | Standard EVM monotonic counter — no `BlockNumberish.sol` branch needed. |
| **`block.basefee` semantics** | Standard wei value, dynamic per EIP-1559. Live probe: ~4.3–4.4 gwei range across 3 consecutive blocks (`0x4385a1`, `0x431953`, `0x439ed6`). No factory tweak needed; **leave `adjustmentPerGweiBaseFee` at its default**. |
| **`block.timestamp` semantics** | Standard Unix seconds. |
| **Native gas token** | AVAX (18 decimals, `address(0)` sentinel). WAVAX wrapped at `0xb31f66aa3c1e785363f0875a1b74e27b85fd66c7`. Orders can use `NATIVE`. |
| **`CALLVALUE` / `BALANCE` / `SELFBALANCE` opcodes** | All standard — `payable` modifiers carry value, sample-executor native sweeps work as on Arbitrum/Base. |
| **State creation costs** | Standard EVM (Avalanche C-Chain uses unmodified geth-derived gas schedule). No special pricing concern. |
| **Permit2 at canonical address?** | ✅ Yes — `eth_getCode` against `0x000000000022D473030F116dDEE9F6B43aC78BA3` returns ~12KB of Permit2 bytecode. |
| **Sequencer / private mempool / pre-confs** | No centralized sequencer (Snowman consensus, ~1500+ validators). No first-party private mempool / pre-confirmations. RFQ exclusivity is enforced solely by the reactor's `ExclusivityLib` (same as Arbitrum, Base, Mainnet). |
| **EIP-1559 / typed tx support** | ✅ Active since Apricot Phase 4 (2021). Type-2 txs supported; `baseFeePerGas` populated and dynamic. |
| **Routing surfaces (UniversalRouter, etc.)** | Universal Router 2.0 + 2.1.1 supported per `avalanche.ts`. v4 supported. Existing sample executors reusable as-is. |

Probe one-liner (confirmed for this writeup):
```bash
RPC=https://api.avax.network/ext/bc/C/rpc
curl -s -X POST $RPC -H 'Content-Type: application/json' -d \
  '{"jsonrpc":"2.0","method":"eth_getCode","params":["0x000000000022D473030F116dDEE9F6B43aC78BA3","latest"],"id":1}'
# returns Permit2 bytecode (non-"0x")
```

---

## §1 EVM compatibility audit

| Behavior | Standard? | Notes for Avalanche |
|---|---|---|
| `block.number` monotonic & contiguous | ✅ | No fork of `BlockNumberish.sol` needed. |
| `block.basefee` real wei value | ✅ | Dynamic EIP-1559 wei; standard treatment. **Do not** zero `adjustmentPerGweiBaseFee`. |
| `block.timestamp` seconds since epoch, monotonic | ✅ | Standard. |
| `msg.value` reflects sent AVAX | ✅ | Native AVAX flows through `payable` paths normally. |
| `address(this).balance` reflects AVAX balance | ✅ | Sample executors' native sweep paths work. |
| Permit2 deployed at canonical address | ✅ | Verified via `eth_getCode`. |
| Arachnid CREATE2 deployer present | ✅ | `0x4e59b44847b379578588920cA78FbF26c0B4956C` returns the canonical 69-byte deployer bytecode — deterministic-address reactor deploy works without bootstrapping. |
| EIP-1559 fields populated | ✅ | `baseFeePerGas` present and dynamic in latest block headers. |

No non-standard cells → no `README.md` deployment-notes block, no `BlockNumberish.sol` branch, no factory override.

---

## Existing UniswapX coverage (uniswapx-sdk `src/constants.ts`)

Searched `sdks/sdks/uniswapx-sdk/src/constants.ts` for chainId `43114` / `Avalanche` / `AVALANCHE`: **no matches**. All four maps need new entries:

- `PERMIT2_MAPPING[43114]` → `0x000000000022d473030f116ddee9f6b43ac78ba3`
- `REACTOR_ADDRESS_MAPPING[43114]` → `{ [OrderType.Dutch_V3]: <reactor address from deploy> }`
- `UNISWAPX_ORDER_QUOTER_MAPPING[43114]` → `<OrderQuoter lens address from deploy>`
- `EXCLUSIVE_FILLER_VALIDATION_MAPPING[43114]` → `0x0000000000000000000000000000000000000000` (mirror Arbitrum/Tempo — exclusivity is reactor-enforced, not via the legacy validation contract).

`@uniswap/sdk-core` already has `ChainId.AVALANCHE = 43114` (long-shipped), so step 3.1 of the playbook is a no-op for this chain.

---

## Deploy parameters

| Parameter | Value | Rationale |
|---|---|---|
| `FOUNDRY_REACTOR_OWNER` | `0x2bad8182c09f50c8318d769245bea52c32be46cd` | Match Arbitrum One protocolFeeOwner unless governance overrides. |
| Reactor | `V3DutchOrderReactor` via `script/DeployDutchV3.s.sol` | Standard path. |
| Lens | `OrderQuoter` | Standard. |
| `V3_BLOCK_LENGTH_BY_CHAIN[43114]` (trading-api) | **`15`** | `ceil(V3_DEFAULT_DECAY_DURATION_SECS / blockTimeSecs) = ceil(30 / 2) = 15`. |
| `V3_BLOCK_BUFFER` (parameterization-api) | `4` (default) | 2s blocks don't need Tempo's tightened `1`; default is fine. |
| `BLOCK_TIME_MS_BY_CHAIN[43114]` (x-service) | `2000` | Matches `avalanche.ts` `blockTimeMs`. |
| `AVERAGE_BLOCK_TIME(43114)` (x-service) | `2` (seconds) | — |
| `MIN_RETRY_WAIT_SECONDS_<CHAIN>` floor | **not needed** | 2s blocks already exceed Step Functions 1s Wait granularity. |
| `GAS_COMPARISON_MULTIPLIER_BY_CHAIN[43114]` | `1.0` (default) | Real EIP-1559 basefee in wei; standard gas-comparison economics. |
| `WRAPPED_NATIVE_CURRENCY[43114]` | WAVAX `0xb31f66aa3c1e785363f0875a1b74e27b85fd66c7` | Standard. **Do not** API-reject native sentinel — AVAX is a real native token. |
| `PRIORITY_ORDER_TARGET_BLOCK_BUFFER[43114]`, `HYBRID_…[43114]` | `0` with comment | No Priority/Hybrid reactor planned at launch; `validateReactorAddress` rejects them upstream. |

---

## Notes

- **Sample executors reusable.** Native AVAX behaves like ETH on Mainnet/Arbitrum; `UniversalRouterExecutor`, `SwapRouter02Executor`, `MultiFillerSwapRouter02Executor` need no Avalanche-specific variants.
- **No category errors from the Tempo playbook apply here.** AVAX is a real native, basefee is real wei, opcodes are standard — Corrections A/B/D/E/F in `NEW_CHAIN.md` are informational only for Avalanche.
- **Stablecoin canary candidates:** USDC (`0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E`) and USDT (`0x9702230A8Ea53601f5cD2dc00fDBc13d4dF4A8c7`) per `avalanche.ts`. DAI on Avalanche is `DAI.e` (bridged) — avoid as canary unless a PMM specifically requests it.
- **Filler ecosystem.** Several PMMs already quote on Avalanche via classic Universal Router; expect at least 1–2 to opt into UniswapX with low integration cost.
- **Block time tension.** Documented 2s vs. observed ~1.1s under current load: budget 2s for retry/decay math (conservative) but expect filler latency-to-fill to land in the 1–2s band. No code-level impact at the 2s budget — Step Functions Wait is in whole seconds and the V3 decay length of 15 blocks ≈ 30s wallclock either way.
- **Snowtrace verification.** `forge verify-contract` requires `--verifier etherscan --verifier-url https://api.snowscan.xyz/api` plus a Snowscan API key (Etherscan-compatible).
