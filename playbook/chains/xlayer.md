# X Layer (chainId 196) — DutchV3 rollout research

**Status:** 🟡 Ready to deploy DutchV3 pending one-time bytecode-level opcode verification (zkEVM lineage). UniswapX has no existing on-chain coverage on 196 — this is a greenfield integration.

**RPC probed:** `https://rpc.xlayer.tech` (public). Universe `getQuicknodeEndpointUrl(UniverseChainId.XLayer)` is the canonical Public/Default/Interface RPC; the public endpoint is sufficient for §0 + §1 probes.

## Existing UniswapX coverage on chainId 196

From `sdks/uniswapx-sdk/src/constants.ts` — **no entries for 196 in any mapping** (`PERMIT2_MAPPING`, `UNISWAPX_ORDER_QUOTER_MAPPING`, `REACTOR_ADDRESS_MAPPING`, `EXCLUSIVE_FILLER_VALIDATION_MAPPING`, V4 mappings). X Layer is not in `NETWORKS_WITH_SAME_ADDRESS`. Greenfield — every mapping needs a fresh entry.

## §0 Pre-integration questionnaire

| Question | X Layer answer |
|---|---|
| **chainId** | `196` (probed `eth_chainId` → `0xc4`) |
| **RPC + explorer** | `https://rpc.xlayer.tech` / `https://web3.okx.com/explorer/x-layer/` |
| **Block time (target)** | ~1s — confirmed via 3 consecutive blocks (59329263→59329265, timestamps 1778098299→1778098301, +1s/block). Universe config says 3000ms but live RPC consistently shows 1s; **use 1000ms** (matches what Step Functions and decay math will actually observe) |
| **Finality model** | zkEVM L2 (Polygon-zkEVM-fork lineage operated by OKX). Sequencer soft-confirmations sub-second; L1 finality after ZK proof submission to Ethereum (~30–60min typical for Polygon-zkEVM-derived chains) |
| **`block.number` semantics** | Standard EVM monotonic counter — confirmed contiguous in 3-block probe. No `BlockNumberish.sol` branch needed |
| **`block.basefee` semantics** | EIP-1559 fields populated; observed `baseFeePerGas = 0x1312d00 = 20_000_000 wei = 0.02 gwei`, **constant across 3 consecutive blocks**. Polygon-zkEVM-derived chains historically run with effectively flat basefee. Recommend `adjustmentPerGweiBaseFee = 0` until basefee is observed varying over a longer window |
| **`block.timestamp` semantics** | Standard Unix seconds, monotonic +1s per block |
| **Native gas token** | OKB (`XLAYER_CHAIN_INFO.nativeCurrency.symbol = 'OKB'`, 18 decimals); WOKB at `0xe538905cf8410324e03A5A23C1c177a474D59b2b` (confirmed has live ~213k OKB balance via `eth_getBalance`). NATIVE sentinel `0x0` is supported in principle |
| **`CALLVALUE` / `BALANCE` / `SELFBALANCE` opcodes** | Expected standard (chain has a native token; Polygon-zkEVM mainnet has been EVM-equivalent since Etrog/Feijoa). **Bytecode-level verification required** before deploy — see Notes |
| **State creation costs** | Standard EVM gas schedule expected; no Tempo-style multiplier. Verify if SSTORE-new-slot exceeds 22.1k during a test fill |
| **Permit2 at canonical address?** | ✅ Yes — `eth_getCode 0x000000000022D473030F116dDEE9F6B43aC78BA3` returned 18 306-byte runtime |
| **Arachnid CREATE2 factory?** | ✅ Yes — `eth_getCode 0x4e59b44847b379578588920cA78FbF26c0B4956C` returned 140-byte runtime; deterministic vanity addresses available |
| **Sequencer / private mempool / pre-confs** | Single OKX-operated zkEVM sequencer, public mempool, no documented pre-confs distinct from soft-confirmations. RFQ `ExclusivityLib` works as on Base/Arbitrum |
| **EIP-1559 / typed tx support** | ✅ Yes — basefee field populated (Polygon-zkEVM Etrog-onward supports EIP-1559 typed txs) |
| **Routing surfaces** | UniversalRouter v2.0 + v2.1.1 supported (`XLAYER_CHAIN_INFO.supportedURVersions`); v4 supported (`supportsV4: true`). Existing `UniversalRouterExecutor` and `SwapRouter02Executor` sample executors usable pending opcode verification |

## §1 EVM compatibility audit

| Behavior | X Layer | Action |
|---|---|---|
| `block.number` monotonic & contiguous | ✅ probed | none |
| `block.basefee` real wei | ⚠️ populated as wei but **observed constant** (0.02 gwei flat across 3 blocks). Polygon-zkEVM mainnet runs an EIP-1559 fee market but in practice basefee rarely moves | Recommend setting `adjustmentPerGweiBaseFee = 0` in `DutchV3OrderFactory` for chainId 196 unless a longer probe window shows real variability. The cosigner can still read `baseFeePerGas` as a tripwire |
| `block.timestamp` Unix seconds, monotonic | ✅ probed | none |
| `msg.value` (`CALLVALUE`) reflects sent OKB | ⚠️ expected ✅ but **unverified on-chain** (zkEVM lineage) | Deploy a tiny payable test contract via Arachnid CREATE2 and assert `msg.value == amount sent` before broadcasting the reactor |
| `address(this).balance` (`BALANCE` / `SELFBALANCE`) reflects OKB balance | ⚠️ expected ✅ — `eth_getBalance` against WOKB contract returns nonzero, which is necessary but not sufficient evidence that the in-EVM `BALANCE` / `SELFBALANCE` opcodes match | Same test contract: assert `address(this).balance` returns the actual balance after a transfer |
| Permit2 at canonical address | ✅ | fresh `PERMIT2_MAPPING[196] = 0x000000000022d473030f116ddee9f6b43ac78ba3` entry needed (196 not in `NETWORKS_WITH_SAME_ADDRESS`) |
| EIP-1559 fields populated | ✅ | cosigner can read `baseFeePerGas` as a tripwire even though it's effectively flat |

If the `CALLVALUE` / `BALANCE` / `SELFBALANCE` test all return standard values (almost certainly the case post-Etrog), this row collapses to "no action" and the chain is effectively Polygon-zkEVM-class for our purposes. If any returns 0 unexpectedly, follow the Tempo template: document caveats in `x-contracts/README.md`, hard-reject NATIVE sentinel at the trading-api boundary, mark sample-executor native-sweep paths as broken on 196.

## Deploy parameters

- **`FOUNDRY_REACTOR_OWNER`**: `0x2bad8182c09f50c8318d769245bea52c32be46cd` (Arbitrum One protocolFeeOwner; reuse unless governance specifies otherwise).
- **OrderQuoter**: redeploy via `script/DeployDutchV3.s.sol` — no shared address exists on 196.
- **`V3_BLOCK_LENGTH_BY_CHAIN[196]`**: `ceil(30 / 1) = 30` blocks (30s wallclock decay at 1s blocks).
- **`V3_BLOCK_BUFFER` (parameterization-api)**: `4` (default; 1s blocks are fast but not sub-second).
- **`BLOCK_TIME_MS_BY_CHAIN[196]` (x-service)**: `1000` (matches probed cadence; **do not** use the 3000ms value from universe `XLAYER_CHAIN_INFO.blockTimeMs` — that field appears stale relative to current chain behavior; flag for follow-up to universe team).
- **`AVERAGE_BLOCK_TIME(196)` (x-service)**: `1` second.
- **`MIN_RETRY_WAIT_SECONDS_<CHAIN>`**: not needed (block time = 1s, ≥ Step Functions Wait granularity).
- **`PRIORITY_ORDER_TARGET_BLOCK_BUFFER[196]`**: `0` with comment — Priority reactor not deployed on 196; `OffChainUniswapXOrderValidator.validateReactorAddress` rejects via the (absent) SDK mapping entry.
- **`HYBRID_ORDER_TARGET_BLOCK_BUFFER[196]`**: `0` with same explanatory comment.
- **`GAS_COMPARISON_MULTIPLIER_BY_CHAIN[196]` (trading-api)**: `0` if basefee remains flat at 0.02 gwei (sub-cent gas regardless of conditions, mirrors Tempo precedent); revisit after a 24h basefee variability probe.
- **Trading-api `CHAIN_INFO_MAP[196]`**: `blockTimeMs: 1000`, `pollingIntervalMs: 250` (matches universe `tradingApiPollingIntervalMs`), tune `orderTypeOverrides[OrderType.DUTCH_V3].deadlineBufferSecs` like Arbitrum.
- **`WRAPPED_NATIVE_CURRENCY[196]`**: `0xe538905cf8410324e03A5A23C1c177a474D59b2b` (WOKB) — only after opcode-verification confirms standard CALLVALUE/BALANCE; if any opcode is non-standard, omit and follow Tempo (no-native) treatment.
- **Stables for canary pairs**: USDT0 `0x779Ded0c9e1022225f8E0630b35a9b54bE713736`, USDC `0x74b7F16337b8972027F6196A17a631aC6dE26d22` (both 6-decimal, sourced from universe `xlayer.ts`).

## Notes

- **zkEVM caveat — verify opcodes before any deploy.** X Layer descends from Polygon zkEVM. Polygon-zkEVM mainnet has been EVM-equivalent since the Etrog/Feijoa upgrades, but each zkEVM fork has its own quirks (e.g., differences in `BLOCKHASH` window, precompile coverage, CALLVALUE rounding under non-ETH gas tokens). Mandatory pre-deploy check: deploy a 30-line Foundry test contract via the Arachnid CREATE2 factory at `0x4e59b44847b379578588920cA78FbF26c0B4956C` that asserts (a) `msg.value` matches sent OKB, (b) `address(this).balance` and `selfbalance()` both reflect a real transfer, (c) `block.number` and `block.timestamp` increment as observed via RPC, (d) Permit2 `permitTransferFrom` round-trips a test ERC20. Only broadcast `DeployDutchV3.s.sol` after all four pass.
- **Basefee is effectively flat at 0.02 gwei.** Same operational posture as Tempo for `adjustmentPerGweiBaseFee` and `GAS_COMPARISON_MULTIPLIER_BY_CHAIN`: zero them out for 196. The cosigner-side `startingBaseFee` tripwire (TODO from Tempo) would catch any future basefee regime change.
- **No existing UniswapX presence.** Unlike Unichain (which had Priority live before V3), X Layer needs every SDK mapping populated from scratch — `PERMIT2_MAPPING`, `UNISWAPX_ORDER_QUOTER_MAPPING`, `REACTOR_ADDRESS_MAPPING`, `EXCLUSIVE_FILLER_VALIDATION_MAPPING`. Treat as a full §3 walkthrough across all six repos in `NEW_CHAIN.md`.
- **Universe `blockTimeMs` mismatch.** `XLAYER_CHAIN_INFO.blockTimeMs = 3000` in universe but live RPC observes 1000ms. File a universe follow-up; in the meantime use 1000ms in x-service / parameterization-api / trading-api so decay math and Step Functions retry cadence match reality.
- **Native sentinel viability is contingent on the opcode test.** If CALLVALUE/BALANCE pass standard, OKB orders via `address(0)` are fine and `WRAPPED_NATIVE_CURRENCY[196] = WOKB` works. If any fails, follow Tempo: hard-reject `0x0` at the trading-api `src/api/quote/schema.ts` boundary and skip the `WRAPPED_NATIVE_CURRENCY` entry.
- **Sample executors are likely usable** (zkEVM-equivalent, native token present), but their native-sweep paths share the same opcode dependency as the reactor — re-verify in the same pre-deploy test.
- **No `disable_uniswapx_xlayer` flag exists yet.** Add one in the config-service registry, default-active = OFF, single runtime step to flip for canary.
