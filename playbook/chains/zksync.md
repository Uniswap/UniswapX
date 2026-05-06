# ZKsync Era (chainId 324) — DutchV3 rollout research

ZKsync Era is a zkEVM rollup operated by Matter Labs. **It is the most complex chain in this rollout list.** Unlike every other chain enumerated in the playbook, zkSync Era is NOT bytecode-compatible with the EVM: contracts are compiled by `zksolc` (not `solc`), the runtime is non-EVM (LLVM-based), and — most importantly for our deploy story — **`CREATE2` address derivation differs from standard EVM**.

Status: **⚠️ Blocked on deploy pipeline** — Permit2, Arachnid CREATE2, and Multicall3 are all present at canonical addresses (verified — see §0), so the chain *runs* UniswapX-style flows; but the Tempo-derived deploy template (`forge script` + `cast` + standard salt mining via `create2crunch`) **will not produce the expected addresses on zkSync Era**. Custom deploy path required. See "Recommended deploy params" below.

---

## §0. Pre-integration questionnaire

| Question | ZKsync Era answer |
|---|---|
| **chainId** | `324` (verified via `eth_chainId` → `0x144`) |
| **RPC + explorer URLs** | `https://mainnet.era.zksync.io` (public) / `https://explorer.zksync.io/` (API: `https://block-explorer-api.mainnet.zksync.io`) |
| **Block time (target)** | ~1s nominal, but **highly variable** (measured 3 consecutive blocks: 69942164→65→66 with deltas of 16s then 3s — sealing is workload-driven, not strict cadence). `universe`'s `zksync.ts` reports `blockTimeMs: 1000`. |
| **Finality model** | Validity-rollup zk proof posted to L1 (~hours for full L1 finality). Sequencer (Matter Labs) provides soft confirmation; UniswapX fill confirmation tracks soft inclusion, same as other rollups. |
| **`block.number` semantics** | Standard EVM monotonic counter — **no `BlockNumberish.sol` branch needed** (unlike Arbitrum's `ArbSys` workaround) |
| **`block.basefee` semantics** | Real wei, dynamic EIP-1559 (measured 0.04525 gwei = `45250000` wei — stable across the 3-block sample). Treat as standard. |
| **`block.timestamp` semantics** | Standard Unix seconds (verified: 1778098300/316/319 monotonic) |
| **Native gas token** | ETH (bridged). `WRAPPED_NATIVE_CURRENCY` = WETH at `0x5AEa5775959fBC2557Cc8789bC1bf90A239D9a91` (per `universe/zksync.ts`) |
| **`CALLVALUE`/`BALANCE`/`SELFBALANCE` opcodes** | Standard semantics — native paths work. (zkSync Era is semantically EVM-equivalent at the opcode level for these.) |
| **State creation costs** | Different from EVM (zk-circuit-bound rather than EVM-gas-bound), but charged through the EIP-1559 gas dimension — economically standard for filler accounting. |
| **Permit2 at canonical address?** | ✅ **Yes** — `eth_getCode` at `0x000000000022D473030F116dDEE9F6B43aC78BA3` returns 9152-byte runtime; `DOMAIN_SEPARATOR()` returns `0xadbe17760d87cd246046b5e2cec81951fac0588a9abe91e30ec1c5bd71aaa14c`. Matter Labs deployed it at the canonical address using a system contract path (not via Arachnid). |
| **Sequencer / private mempool / pre-confs** | Single sequencer (Matter Labs), public mempool exposed via RPC; no native pre-confs. ExclusivityLib filler exclusivity sufficient. |
| **EIP-1559 / typed tx support** | ✅ Yes — `baseFeePerGas` populated. zkSync also has type `0x71` (EIP-712) txs; fillers using standard type-2 are supported. |
| **Routing surfaces (UniversalRouter, etc.)** | UniversalRouter v2.0 only (per `zksync.ts: supportedURVersions`). v4 NOT supported (`supportsV4: false`). Sample executors recompile-required (zksolc), see caveats below. |

Probe one-liner used:
```bash
RPC=https://mainnet.era.zksync.io
# All three return non-empty bytecode:
for addr in 0x000000000022D473030F116dDEE9F6B43aC78BA3 \
            0x4e59b44847b379578588920cA78FbF26c0B4956C \
            0xcA11bde05977b3631167028862bE2a173976CA11; do
  curl -s -X POST $RPC -H 'Content-Type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getCode\",\"params\":[\"$addr\",\"latest\"],\"id\":1}"
  echo
done
```

---

## §1. EVM compatibility audit — **WITH ZKSYNC CAVEATS**

| Behavior | ZKsync Era | UniswapX impact |
|---|---|---|
| `block.number` monotonic & contiguous | ✅ | None — default branch in `BlockNumberish.sol` correct |
| `block.basefee` real wei value | ✅ dynamic (~0.045 gwei observed) | None — leave `adjustmentPerGweiBaseFee` at default |
| `block.timestamp` seconds since epoch | ✅ | None |
| `msg.value` / `BALANCE` / `SELFBALANCE` | ✅ standard | None — native paths functional |
| Permit2 at canonical address | ✅ Yes | None at runtime — reactor binds to canonical `0x0000…7BA3` |
| EIP-1559 fields populated | ✅ Yes | Cosigner can read `baseFeePerGas` normally |

So far so good — **at runtime**, zkSync Era looks like a standard EVM rollup. The complications are entirely in the deploy pipeline:

> ### ⚠️ Build / deploy caveats — read before touching
>
> 1. **Compiler is `zksolc`, not `solc`.** Foundry's `forge build` produces solc EVM bytecode that **will not run on zkSync Era**. You must use [foundry-zksync](https://github.com/matter-labs/foundry-zksync) or [hardhat with @matterlabs/hardhat-zksync](https://docs.zksync.io/build/tooling/hardhat). The same source compiles, but the produced artifact is a zkEVM bytecode object with a different bytecode hash.
>
> 2. **CREATE2 derivation is non-EVM.** zkSync Era uses:
>    `keccak256(keccak256("zksyncCreate2") || sender || salt || bytecodeHash || keccak256(constructorInput))`
>    where `bytecodeHash` is the **zkEVM** bytecode hash, not `keccak256(initCode)`. This means:
>    - Salt mining via `create2crunch` (which assumes standard `keccak256(0xff || ... || keccak256(initCode))`) **produces wrong addresses on zkSync**.
>    - Even though Arachnid's factory at `0x4e59…56C` is present (69-byte runtime — verified), it is the **EVM-bytecode** factory; calling it works but produces an address derived per Arachnid's EVM rule, not zkSync's native CREATE2 rule. In practice we'd be using it as a passthrough deployer for zkEVM-compiled bytecode, in which case the produced contract address must be computed using zkSync's derivation, NOT Arachnid's `keccak256(0xff||...)` formula. This easy-to-get-wrong divergence is the single biggest implementor footgun on this chain.
>    - The native zkSync `ContractDeployer` system contract at `0x0000000000000000000000000000000000008006` is the canonical CREATE2 path on this chain — reactor + OrderQuoter should be deployed via it (or via foundry-zksync's `--zksync` flag, which routes through it).
>
> 3. **OrderQuoter / reactor address won't match other chains.** Even if we deploy with the same source + salt as on Mainnet/Arbitrum, the resulting address differs (different bytecode hash, different derivation). **Drop the "vanity address shared across chains" expectation** — the SDK's `UNISWAPX_ORDER_QUOTER_MAPPING` and `REACTOR_ADDRESS_MAPPING` must have an explicit per-324 entry, NOT inherit via `constructSameAddressMap`.
>
> 4. **Sample executors will need re-audit.** The reactor's correctness is preserved (Solidity semantics are equivalent), but anything that reads `extcodehash`, hardcodes init-code hashes (e.g., Uniswap v2-style pair address derivation), or relies on `selfdestruct` will misbehave. UniswapX core does none of these, but `UniversalRouterExecutor` / `SwapRouter02Executor` may indirectly via the routers they call.

---

## Existing UniswapX coverage on ZKsync Era

From `sdks/uniswapx-sdk/src/constants.ts` (verified at `/Users/cody.born/repos/uniswapx-sdk/src/constants.ts`):

| Mapping | Entry for chainId 324 |
|---|---|
| `PERMIT2_MAPPING` | ❌ **missing** — but Permit2 IS deployed at the canonical address. Add as an explicit `324:` entry rather than via `NETWORKS_WITH_SAME_ADDRESS` (defensive: makes it obvious that this chain has a non-standard deploy story even though Permit2 happens to be canonical). |
| `UNISWAPX_ORDER_QUOTER_MAPPING` | ❌ **no entry** (and would NOT be the same `0xc6ef…` address as Mainnet — see caveat 3 above) |
| `REACTOR_ADDRESS_MAPPING` | ❌ **no entry** — greenfield deploy required |
| `EXCLUSIVE_FILLER_VALIDATION_MAPPING` | inherited via `constructSameAddressMap` default → `0x8A66A74e15544db9688B68B06E116f5d19e5dF90` (very likely NOT actually deployed at this address on zkSync — DO NOT rely on; explicitly set to `0x0` like Arbitrum until verified) |

**DutchV3 is greenfield on zkSync Era.** No prior reactor, no OrderQuoter; SDK currently has zero entries for chainId 324.

---

## Recommended deploy params

**Honest assessment: the Tempo-template deploy pipeline (`script/DeployDutchV3.s.sol` via vanilla `forge script` + canonical Arachnid factory + create2crunch salt mining) WILL NOT WORK on zkSync Era.** A different deploy path is needed.

| Parameter | Value / approach | Rationale |
|---|---|---|
| **Toolchain** | `foundry-zksync` (fork of foundry with `--zksync` flag) OR hardhat + `@matterlabs/hardhat-zksync` | `forge` mainline emits solc EVM bytecode; we need zksolc zkEVM bytecode |
| **CREATE2 path** | zkSync `ContractDeployer` system contract (`0x...8006`) via `foundry-zksync`'s built-in routing | Native derivation; salt-mining tooling for it exists in `@matterlabs/zksync-contracts` |
| **Vanity / cross-chain address parity** | **Abandon** — accept a different reactor + OrderQuoter address than other chains | Bytecode hash differs from solc artifacts; cross-chain salt mining is intractable |
| `FOUNDRY_REACTOR_OWNER` | `0x2bad8182c09f50c8318d769245bea52c32be46cd` | Same protocolFeeOwner as Arbitrum One — unchanged |
| `adjustmentPerGweiBaseFee` (in `DutchV3OrderFactory`) | **default** (non-zero) | Basefee is real, dynamic wei (45250000 observed) — standard V3 gas-adjustment math applies |
| `V3_BLOCK_LENGTH_BY_CHAIN[324]` | **30** (= `ceil(30s / 1s)` at `V3_DEFAULT_DECAY_DURATION_SECS = 30`) | Matches `universe/zksync.ts` `blockTimeMs: 1000`. Caveat: zkSync sealing is variable; consider tuning down or pegging decay to wallclock if drift is observed in canary. |
| `V3_BLOCK_BUFFER` (parameterization-api) | **4** (default) | 1s blocks — no Tempo-style override needed |
| `BLOCK_TIME_MS_BY_CHAIN[324]` (x-service) | `1000` | Matches `universe/zksync.ts` |
| `MIN_RETRY_WAIT_SECONDS_<CHAIN>` floor | **not needed** | Block time ≥ 1s |
| `GAS_COMPARISON_MULTIPLIER_BY_CHAIN[324]` (trading-api) | `1.0` (default) | Gas is real and meaningful |
| `WRAPPED_NATIVE_CURRENCY[324]` | `0x5AEa5775959fBC2557Cc8789bC1bf90A239D9a91` (WETH) | Per `universe/zksync.ts` |
| Native sentinel (`address(0)`) at trading-api boundary | **allow** | Has a real native token (ETH) |

**Implementor checklist before starting work on chainId 324:**
1. Set up `foundry-zksync` locally; verify `forge build --zksync` produces zkEVM artifacts for `V3DutchOrderReactor` + `OrderQuoter`. (Likely friction: x-contracts pins solc 0.8.29 — confirm zksolc version compatibility.)
2. Re-audit any inherited submodule (permit2, solmate, OZ) for zkSync-incompatible patterns (notably `selfdestruct`, init-code-hash assumptions in factories).
3. Decide: separate `script/DeployDutchV3.zksync.s.sol` (preferred, mirrors Tempo template structure but routes through zksolc) vs. ad-hoc hardhat deploy. The first is more consistent with the rest of the rollout; the second is faster.
4. Compute the expected reactor + OrderQuoter addresses using zkSync's CREATE2 rule before deploying — do NOT rely on Arachnid's formula. Cross-check against `@matterlabs/zksync-contracts`'s address-prediction utilities.
5. Add per-324 entries to all three SDK mappings as explicit literals (no `constructSameAddressMap`), and zero out `EXCLUSIVE_FILLER_VALIDATION_MAPPING[324]` until that contract is independently deployed and verified.

---

## Notes

**Why this chain is "blocked" but not "out of scope":** Runtime semantics are EVM-compatible enough that the reactor logic is correct; the order-flow trading API can quote and serve orders identically once a reactor is deployed. The blocker is mechanical (build pipeline + deploy tooling), not architectural. A pod that's done one zkSync deploy before could likely complete this in 1–2 days; a pod cold-starting on zkSync should budget a week including foundry-zksync setup, submodule audits, and post-deploy SDK wiring. **Recommend deferring zkSync to last in the rollout sequence** so it doesn't gate the simpler chains.

**Sequencer trust.** Matter Labs runs the sole sequencer. UniswapX exclusivity protects winning fillers within an order; sequencer reordering risk is at parity with other single-sequencer rollups (Base, Optimism). No additional mitigation beyond `ExclusivityLib`.
