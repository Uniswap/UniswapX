# Celo (chainId 42220) — DutchV3 rollout research

Status: 🟡 Has caveats — multi-gas-token model, recent L1→L2 (OP-stack) migration, and short block time. RPC probe confirms basics; readiness depends on whether we choose to support a no-NATIVE chain whose gas token is also a routable ERC20.

Probed `https://forno.celo.org` on 2026-05-01.

## §0 Pre-integration questionnaire

| Question | Celo answer |
|---|---|
| **chainId** | `42220` (verified via `eth_chainId`) |
| **RPC + explorer URLs** | RPC: `https://forno.celo.org` (also `https://celo-mainnet.infura.io/v3/<key>` and the Quicknode endpoint per universe). Explorer: `https://celoscan.io/`, API `https://api.celoscan.io` |
| **Block time (target)** | **~1s empirically.** 30-block delta = 30s; 3 consecutive blocks (66197554/55/56) had timestamps 1s apart. Universe's `celo.ts` still claims `blockTimeMs: 5000` — that value is **stale**. Celo migrated from 5s to ~1s blocks in late 2024, then to OP-stack L2 in early 2025. Use 1000ms in our configs. |
| **Finality model** | OP-stack L2 (post-migration). 1s block time, sequencer-driven. L1 finality on Ethereum (~12 min). For RFQ fills the relevant safety window is sequencer confirmation, not Ethereum L1. |
| **`block.number` semantics** | Standard EVM monotonic counter. `BlockNumberish.sol` needs no new branch. (No `ArbSys`-style override on Celo's OP-stack deployment.) |
| **`block.basefee` semantics** | Real wei value, EIP-1559 active. Latest probe: `0x2e90edd000` = **200 gwei**. Comparable to Polygon — high-magnitude basefee in real wei, so DutchV3 gas-adjustment math should run normally (`adjustmentPerGweiBaseFee != 0`). |
| **`block.timestamp` semantics** | Standard Unix seconds, monotonic. |
| **Native gas token** | **Non-standard.** CELO is the gas token and *also* has an ERC20 precompile at `0x471EcE3750Da237f93B8E339c536989b8978a438` (5172-byte runtime; verified). In addition, Celo's "fee currency" mechanism lets txs pay gas in cUSD, cEUR, cREAL, USDC, USDT. From a UniswapX standpoint the native sentinel `address(0)` is a category error here — see Notes. |
| **`CALLVALUE` / `BALANCE` / `SELFBALANCE`** | Standard (real wei). Reactor `payable` modifiers and the leftover-balance refund branch in `BaseReactor.sol` work normally — but only relevant if the order's input token is the CELO precompile, which behaves like an ERC20, not as `msg.value`. |
| **State creation costs** | Standard EVM (no Tempo-style 12.5× multiplier known). |
| **Permit2 at canonical address?** | ✅ Yes. `eth_getCode("0x000000000022D473030F116dDEE9F6B43aC78BA3")` returned 18306 bytes of runtime. |
| **Sequencer / private mempool / pre-confs** | OP-stack L2 with a single sequencer (post-migration). Standard OP-stack mempool semantics — ExclusivityLib protections apply identically to Optimism/Base. |
| **EIP-1559 / typed tx support** | ✅ Yes. `baseFeePerGas` populated on every probed block. |
| **Routing surfaces (UniversalRouter, etc.)** | UniversalRouter v2.0 + v2.1.1 both supported per `celo.ts` (`supportedURVersions`). UniswapV4 supported (`supportsV4: true`). Trading-API already references `UNIVERSAL_ROUTER_ADDRESS(..., 42220)`. Sample executors will need ERC20-only sweep variants if used (CELO-as-ERC20 is the closest thing to a "native" sweep). |

## §1 EVM compatibility audit

| Behavior | Celo | UniswapX impact |
|---|---|---|
| `block.number` monotonic & contiguous | ✅ standard | None |
| `block.basefee` real wei value | ✅ standard (200 gwei probed) | Use normal `adjustmentPerGweiBaseFee` (do NOT zero) |
| `block.timestamp` seconds since epoch | ✅ standard | None |
| `msg.value` reflects sent CELO | ✅ standard for the native CELO gas token | But because the native and the canonical CELO ERC20 are the same asset at two interfaces, orders that intend to swap "CELO" must use the ERC20 precompile address, not `address(0)` |
| `address(this).balance` reflects CELO balance | ✅ standard | Same caveat — sample-executor native sweeps work but reach the same asset twice |
| Permit2 deployed at canonical | ✅ verified | None |
| Arachnid CREATE2 deployer | ✅ at `0x4e59...956C` (140-byte runtime probed) | Standard CREATE2 deploy path works |
| EIP-1559 fields populated | ✅ | Cosigner can read live basefee normally |
| OP-stack L2 predeploys present | ✅ `L1Block` at `0x4200000000000000000000000000000000000015` (4120 bytes) | Confirms post-migration L2 — relevant for any code that introspects L2 system contracts |

## Existing UniswapX coverage on chainId 42220

- `@uniswap/uniswapx-sdk` (`/Users/cody.born/repos/sdks/sdks/uniswapx-sdk/src/constants.ts`):
  - `NETWORKS_WITH_SAME_ADDRESS`: **does NOT include Celo** → no implicit Permit2 / OrderQuoter / Dutch v1 reactor entries.
  - `PERMIT2_MAPPING`: **no 42220 entry**.
  - `UNISWAPX_ORDER_QUOTER_MAPPING`: **no 42220 entry**.
  - `REACTOR_ADDRESS_MAPPING`: **no 42220 entry** — no Dutch / Dutch_V2 / Dutch_V3 / Priority / Hybrid reactors registered.
- `x-contracts`: no Celo references in src or scripts (only the playbook README row).
- `trading-api`: chainId 42220 is recognized by the classic-swap surface (`UNIVERSAL_ROUTER_ADDRESS(version, 42220)`, `ChainId.CELO ↔ Chain.Celo` mapping in `lib/clients/graphql/uniswap/UniswapGraphqlClient.ts`), and the test suite's chain validators list it. UniswapX is **not** wired for Celo.
- `x-service` / `x-parameterization-api`: no Celo entries (grep clean).
- universe (`packages/uniswap`) already filters Celo out of `WrapUnwrapOrder.test.ts` and has `// Celo does not have native currency` carve-outs in handler tests — the precedent for treating Celo as no-native-sentinel is already established.

Net: Celo is an **uncovered chain** for UniswapX. All §3 changes from `NEW_CHAIN.md` apply.

## Deploy params

Standard `script/DeployDutchV3.s.sol` invocation. Permit2 + Arachnid CREATE2 deployer present, so the script's CREATE2 path works as on other chains.

```bash
FOUNDRY_REACTOR_OWNER=0x2bad8182c09f50c8318d769245bea52c32be46cd \
forge script script/DeployDutchV3.s.sol \
    --rpc-url https://forno.celo.org \
    --broadcast \
    --private-key $DEPLOYER_KEY
```

Verify on `https://celoscan.io/`. Also deploy `OrderQuoter` lens and record both addresses for the `uniswapx-sdk` mappings.

## Notes (read before estimating)

- **L1 → L2 migration is complete.** Celo migrated from a standalone L1 to an OP-stack L2 in early 2025. The chain we're connecting to via `https://forno.celo.org` returns chainId `42220` and exposes the OP-stack `L1Block` predeploy at `0x4200…0015` — confirming we're talking to the L2. Any historical "Celo L1" treatment in our codebase (5s blocks, BFT finality assumptions) is stale. `universe/packages/uniswap/.../celo.ts` still has `networkLayer: NetworkLayer.L1` and `blockTimeMs: 5000` — both are outdated and should be flagged on the universe side as part of the rollout.
- **Block time is ~1s, not 5s.** Verified empirically (30-block delta = 30s; 3-block deltas = 1s each). This puts Celo in the "sub-2s blocks" bucket alongside Unichain and Tempo, so:
  - Apply Correction D from `NEW_CHAIN.md`: add a chain-scoped `MIN_RETRY_WAIT_SECONDS_CELO` floor in `x-service` `calculateDutchRetryWaitSeconds` so Step Functions Wait states don't round to 0.
  - `V3_BLOCK_LENGTH_BY_CHAIN` for Celo: 30 blocks (1s × 30 = 30s default decay), not 60.
  - `V3_BLOCK_BUFFER` likely 2 (closer to Tempo's 1 than Mainnet's 4) — tune during canary.
- **Multi-gas-token model is the dominant Celo specifics issue.** CELO is both (a) the native gas token (`msg.value` semantics work) and (b) an ERC20 at `0x471E…a438` (the precompile). Independently, Celo lets txs pay gas in cUSD / cEUR / cREAL / USDC / USDT via the fee-currency mechanism, so the *filler's* gas accounting may not be in CELO at all. Implications:
  - The native sentinel `address(0)` is **ambiguous** on Celo (CELO has both an ERC20 address and `msg.value` semantics). Mirror universe's existing pattern: reject `0x0` token addresses at the trading-api boundary for chainId 42220 and require swappers to specify the CELO ERC20 precompile address explicitly. See Correction E in `NEW_CHAIN.md`.
  - In `WRAPPED_NATIVE_CURRENCY[CELO]`: do NOT populate, or populate with the CELO ERC20 precompile (since CELO *is* its own wrapped form). Universe's `wrappedNativeCurrency` already uses the precompile — match that.
  - Sample executors that read `address(this).balance` to sweep native are technically functional but redundant; ERC20 sweep against the CELO precompile is the canonical path. Document for PMMs.
  - Filler economics: a filler paying tx gas in cUSD pays the basefee × gas × cUSD/CELO oracle, not directly in CELO. Doesn't break our pricing model — `block.basefee` is still in wei of CELO — but be aware when reasoning about filler P&L during canary.
- **Basefee is real wei (200 gwei probed).** Unlike Tempo, do **not** zero out `adjustmentPerGweiBaseFee` in `DutchV3OrderFactory`. Standard V3 gas-adjustment math applies. `GAS_COMPARISON_MULTIPLIER_BY_CHAIN[CELO] = 1.0` (default).
- **Universe metadata is partly stale and should be refreshed alongside the rollout** (`networkLayer`, `blockTimeMs`). Not blocking for x-contracts deploy but should be in scope for the universe-side PR.

---

Readiness: 🟡 ready to proceed; primary work is multi-gas-token treatment + sub-2s retry floor, plus refreshing stale universe metadata (5s→1s, L1→L2). Path: `/Users/cody.born/repos/x-contracts/playbook/chains/celo.md`.
