# UniswapX New-Chain Integration Playbook

This document is the runbook for bringing up UniswapX on a new EVM chain. It was distilled from the Tempo (chainId 4217) rollout (Linear TRA2-12) and is intended to make Avalanche, Robinhood, and any subsequent chain ~80% mechanical.

**Audience**: an engineer or pod that is about to enable UniswapX on a chain that already has Permit2 deployed (or is willing to deploy it) and has at least one PMM/filler willing to integrate.

**Scope**: end-to-end — reactors, SDK, services, trading API, rollout. Includes the gotchas that cost us cycles on Tempo so future integrations don't repeat them.

---

## 0. Pre-integration questionnaire

Answer these before writing a single line of code. Most can be resolved against the chain's docs + a curl against its public RPC. The Tempo answers are filled in as a worked example so future readers can compare.

| Question | Why it matters | Tempo answer |
|---|---|---|
| **chainId** | Used in every repo's enums, every cosigner signature, every reactor deploy | `4217` |
| **RPC + explorer URLs** | Needed for env vars and integ tests | `https://rpc.tempo.xyz` / `https://explore.mainnet.tempo.xyz` |
| **Block time (target)** | Drives `BLOCK_TIME_MS_BY_CHAIN`, decay block-length math, status-polling cadence, Step Functions retry backoff | ~500ms |
| **Finality model** | Drives min confirmations for fills; reorg risk | Deterministic sub-second via Simplex BFT |
| **`block.number` semantics** | Decides whether `BlockNumberish.sol` needs a new branch (Arbitrum special-cases via `ArbSys`) | Standard EVM monotonic counter — no change needed |
| **`block.basefee` semantics** | Drives V3 reactor's `_updateWithGasAdjustment`; tells us whether to set `adjustmentPerGweiBaseFee = 0` | Constant `2e10` in **attodollars/gas** (1e-18 USD), NOT wei |
| **`block.timestamp` semantics** | Deadline math safety | Standard Unix seconds |
| **Native gas token** | Decides whether orders can use the `NATIVE` sentinel `address(0)` | None — Tempo uses TIP-20 USD stablecoins via Fee AMM |
| **`CALLVALUE` / `BALANCE` / `SELFBALANCE` opcodes** | Multiple reactor + sample-executor code paths read these | All three return 0 — `payable` modifiers no-op, sample-executor native sweeps inert |
| **State creation costs** | Affects filler cold-fill economics | 12.5× higher (250K gas/new slot); economically immaterial at constant low basefee |
| **Permit2 at canonical address?** | Reactor binds to a fixed Permit2 address | ✅ Yes (verified via `eth_getCode`) |
| **Sequencer / private mempool / pre-confs** | Affects RFQ exclusivity protection beyond the reactor's `ExclusivityLib` | Multi-validator with VRF leader election, no private mempool — same as other UniswapX chains |
| **EIP-1559 / typed tx support** | RPC compatibility for fillers | Yes (basefee constant, but fields are populated) |
| **Routing surfaces (UniversalRouter, etc.)** | Whether existing sample executors can be reused | Sample executors require ERC20-only sweep variants on Tempo; PMMs typically roll their own |

A useful one-liner to probe basefee + block time + block-number monotonicity in one shot:

```bash
RPC=https://rpc.tempo.xyz
N=$(curl -s -X POST $RPC -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  | python3 -c "import sys,json;print(int(json.load(sys.stdin)['result'],16))")

curl -s -X POST $RPC -H 'Content-Type: application/json' \
  -d "[$(printf '{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"0x%x\",false],\"id\":%d},' $((N-2)) 1 $((N-1)) 2 $N 3 | sed 's/,$//')]" \
  | python3 -c "import sys,json;[print(int(b['result']['number'],16),int(b['result'].get('timestampMillis',b['result']['timestamp']),16),b['result']['baseFeePerGas']) for b in json.load(sys.stdin)]"
```

Confirms: monotonic block number, real block time deltas, basefee value.

---

## 1. EVM compatibility audit

Run this audit against the chain's docs **and** by reading bytecode behavior on its public RPC. The two should agree; if they don't, trust the bytecode.

| Behavior | Standard EVM | UniswapX impact if non-standard |
|---|---|---|
| `block.number` monotonic & contiguous | ✅ | Need a new branch in `src/base/BlockNumberish.sol` mirroring the Arbitrum `ArbSys` special-case |
| `block.basefee` real wei value | ✅ | If constant or zero or denominated differently (Tempo: attodollars), set `adjustmentPerGweiBaseFee = 0` in `DutchV3OrderFactory` for that chain so gas-adjustment math is a no-op |
| `block.timestamp` seconds since epoch, monotonic | ✅ | Deadline checks rely on this; non-standard would break order expiry |
| `msg.value` (`CALLVALUE` opcode) reflects sent ETH | ✅ | If always 0 (Tempo): `payable` modifiers on reactor are no-ops, but the leftover-balance refund branch in `BaseReactor.sol:126` becomes dead code (harmless) — and **orders cannot use NATIVE sentinel** |
| `address(this).balance` (`BALANCE`/`SELFBALANCE`) reflects ETH balance | ✅ | If always 0 (Tempo): reactor's refund branch is dead; sample executors `UniversalRouterExecutor`, `SwapRouter02Executor`, `MultiFillerSwapRouter02Executor` have broken native sweeps — PMMs need ERC20-balance variants |
| Permit2 deployed at canonical address | ✅ on most chains | If absent, deploy permit2 first via the canonical CREATE2 deployer, then UniswapX reactor binds to it |
| EIP-1559 fields populated | ✅ | Cosigner reads `baseFeePerGas` from latest block to set `startingBaseFee` (or as a tripwire) |

**Action items if any cell answers non-standard:**
1. Document in `x-contracts/README.md` under a "<Chain> deployment notes" section, mirroring the Tempo block.
2. If `block.number` is non-standard, fork `BlockNumberish.sol` with a new branch.
3. If `BALANCE`/`CALLVALUE` are non-standard, document sample-executor caveats and ensure the trading-api API boundary rejects native sentinel for that chain.
4. Set `adjustmentPerGweiBaseFee = 0` in `DutchV3OrderFactory` for any chain where basefee is constant, zero, or denominated non-standardly.

---

## 2. Repo dependency graph

Order matters because of inter-repo dependencies. The graph below is the "right" order; you can parallelize most of step 3 onward, but step 1 → 2 are gates.

```
1. @uniswap/sdk-core
       │  (adds ChainId.X enum + addresses)
       ▼
2. x-contracts                     ┐
       │  (deploy V3DutchOrderReactor + OrderQuoter)
       │
       ▼ (record reactor + quoter addresses)
3. @uniswap/uniswapx-sdk           │  parallel
       │  (register addresses)     │  with
       ▼                           │  step 3
4. x-parameterization-api          │
       │                           │
       ▼                           │
5. x-service                       │
       │                           │
       ▼                           │
6. trading-api (b/packages/services/trading) ┘
```

Steps 4–6 can be developed in parallel and pinned to the SDK canary release from step 3 in dev.

---

## 3. Per-repo changes

For each repo: branch off latest `main` as `<chain>-uniswapx` (e.g., `tempo-uniswapx`), commit, do **not** push until the cross-repo set is reviewed together.

### 3.1 `@uniswap/sdk-core` (in the sdks monorepo)

**Files:** `sdks/sdk-core/src/chains.ts`, `sdks/sdk-core/src/addresses.ts`

- Add `<CHAIN> = <chainId>` to the `ChainId` enum.
- Append to `SUPPORTED_CHAINS`.
- Add a `<CHAIN>_ADDRESSES` block in `addresses.ts` covering v3/v4/router contracts that exist on the chain (or empty placeholders).
- Wire into `CHAIN_TO_ADDRESSES_MAP`.
- **If the chain has no native token**, omit the WETH9 entry. There's no per-chain "native currency" map that needs special handling — just don't add an entry for chains without a native (Tempo precedent: PR #540 explicitly removed a WETH9 entry that had been added in error).
- Publish to npm before the next repo can pin against `ChainId.<CHAIN>`. If you want to unblock parallel work, downstream repos can use the numeric chain id with a `// TODO: ChainId.<CHAIN> once sdk-core is bumped` comment.

**Tempo note**: already on main as PRs #533 + #540.

### 3.2 `x-contracts`

**Files:** `script/DeployDutchV3.s.sol` (header comment), `README.md`

- Add a "<Chain> deployment notes" section in `README.md` covering: ERC20-only constraints, basefee/block.number/CALLVALUE/BALANCE behavior, sample-executor caveats.
- Add a copy-paste-runnable Tempo-style deploy invocation comment block to `script/DeployDutchV3.s.sol`. Required env var: `FOUNDRY_REACTOR_OWNER` (use the same protocolFeeOwner address as Arbitrum One: `0x2bad8182c09f50c8318d769245bea52c32be46cd`, unless governance has decided otherwise for the new chain).
- If the chain requires a `BlockNumberish.sol` branch (non-standard `block.number`), add it.

**Deploy command (production):**
```bash
FOUNDRY_REACTOR_OWNER=0x2bad8182c09f50c8318d769245bea52c32be46cd \
forge script script/DeployDutchV3.s.sol \
    --rpc-url <CHAIN_RPC> \
    --broadcast \
    --private-key $DEPLOYER_KEY
```

Same script also deploys the OrderQuoter lens (or use `script/QuoteV3Order.s.sol` / a future dedicated lens deploy script). Verify on the chain's explorer; record the addresses.

**Don't** spend cycles wiring this into the `/contracts` deployment-orchestration repo unless that repo's UniswapX deployer support has already landed — on Tempo we hit a `compilation_restrictions` conflict in `foundry.toml` where uniswapx (solc 0.8.30, no via_ir) and permit2 (solc 0.8.17, via_ir) couldn't coexist on shared interface files. The direct `x-contracts` deploy route is the proven path.

### 3.3 `@uniswap/uniswapx-sdk`

**File:** `src/constants.ts`

- Add the chain id to `PERMIT2_MAPPING` (use `constructSameAddressMap` if Permit2 is at canonical, otherwise add as a separate entry).
- Add `[OrderType.Dutch_V3]: <reactor address>` to `REACTOR_ADDRESS_MAPPING` for the new chain id.
- Add the OrderQuoter address to `UNISWAPX_ORDER_QUOTER_MAPPING`.
- **Do NOT** add entries for `OrderType.Priority`, `OrderType.Dutch_V2`, etc., unless those reactors are also deployed on the chain. The absence of an entry is what makes `OffChainUniswapXOrderValidator.validateReactorAddress` (in x-service) reject those order types for the chain — that's the upstream guard that protects the priority/hybrid path.

**Tests:**
- Assert `V3DutchOrderBuilder(<chainId>)` resolves the reactor.
- Assert `getReactor(<chainId>, OrderType.Dutch_V3)` returns the expected address.
- Add a decay block-delta test using a chain-realistic block length (e.g. 60 blocks at 0.5s = 30s wallclock for Tempo).

### 3.4 `x-parameterization-api`

**Files:** `lib/util/chains.ts`, `lib/config/chains.ts`, `lib/constants.ts`, `lib/handlers/hard-quote/handler.ts`

- Add `<CHAIN> = <chainId>` to the `ChainId` enum in `lib/util/chains.ts`. **Also** add to `supportedChains` in `lib/config/chains.ts` (separate file, both required — Joi `chainId` validator gates inbound requests on the latter).
- Add the chain to `ID_TO_NETWORK_NAME`.
- Add `RPC_<chainId>` to `.env.example`.
- Per-chain `V3_BLOCK_BUFFER` (in `lib/constants.ts` as a map): default 4, but tune per chain. Tempo uses 1 because of fast blocks.
- Per-chain block time entry in `getBlockTimeSecs(chainId)` so `getDecayBlockLength(chainId) = ceil(V3_DEFAULT_DECAY_DURATION_SECS / blockTimeSecs)` produces sensible block counts. `V3_DEFAULT_DECAY_DURATION_SECS = 30` is the standard wallclock decay.

**Do NOT touch:**
- `lib/cron/fade-rate-v2.ts` — filler circuit-breaker logic, intentionally chain-agnostic. New chains flow through automatically (the SQL view's testnet-exclusion list correctly omits mainnet chain ids).
- `lib/repositories/fades-repository.ts` — same.

**V3 RFQ cosigning** is already implemented (TRA2-12). No further action needed unless adding a brand-new order type. If you do extend it: see Correction A below — V3 invariants are the **same direction** as V2 (swapper-improvement), not opposite.

### 3.5 `x-service`

**Files:** `lib/util/chain.ts`, `lib/util/constants.ts`, `lib/handlers/check-order-status/util.ts`, `lib/handlers/constants.ts`, `.env.example`

- `lib/util/chain.ts`: `<CHAIN> = <chainId>` to enum + `SUPPORTED_CHAINS`.
- `lib/util/constants.ts`: `BLOCK_TIME_MS_BY_CHAIN[CHAIN] = <ms>` and `OLDEST_BLOCK_BY_CHAIN[CHAIN] = <recent block>`.
- `lib/handlers/check-order-status/util.ts`: `AVERAGE_BLOCK_TIME(CHAIN)` returning the chain's block time in seconds.
- **Sub-second blocks**: if the chain's block time is < 1s, add a chain-scoped minimum wait floor in `calculateDutchRetryWaitSeconds` (e.g. `MIN_RETRY_WAIT_SECONDS_<CHAIN> = 2`). Step Functions Wait state granularity is whole seconds; sub-second values round to 0 → hot loop. Apply the floor only to the affected chain — applying globally tightens existing chains unnecessarily (the Tempo PR caught this on review).
- `lib/handlers/constants.ts`: `PRIORITY_ORDER_TARGET_BLOCK_BUFFER` and `HYBRID_ORDER_TARGET_BLOCK_BUFFER` are typed `Record<ChainId, number>` with no fallback, so the build won't pass without an entry. If the chain doesn't support priority/hybrid orders (no reactor deployed): set the entry to `0` with a comment explaining the value is unreachable because `OffChainUniswapXOrderValidator.validateReactorAddress` rejects orders whose reactor isn't in the SDK mapping.
- `.env.example`: `RPC_<chainId>=<rpcUrl>`.
- CDK is already loop-driven over `SUPPORTED_CHAINS`; no infra changes needed unless you find hardcoded chain logic.

### 3.6 `b/packages/services/trading` (Trading API)

**Files:** `src/models/chain.ts`, `src/api/quote/schema.ts`, `src/lib/util/dutch.ts`, `src/lib/constants.ts`, `src/core/order-factory/dutch/DutchV3OrderFactory.ts`, `src/core/quoters/rfq/RFQQuoter.ts`

- `src/models/chain.ts`: add `ChainId.<CHAIN>` to `UNISWAPX_SUPPORTED_CHAIN_IDS`. Add a `CHAIN_INFO_MAP` entry: `blockTimeMs`, `pollingIntervalMs`, `orderTypeOverrides[OrderType.DUTCH_V3].deadlineBufferSecs` tuned to the chain.
- **If the chain has no native token**: do **not** populate `WRAPPED_NATIVE_CURRENCY[CHAIN]`. Don't pick "the closest stablecoin" as a stand-in — that misleads clients. Instead, in `src/api/quote/schema.ts`, hard-reject requests with `tokenIn === '0x0000000000000000000000000000000000000000'` or `tokenOut === '0x0...'` for that chain at the API boundary. Defense in depth above the reactor.
- `src/lib/constants.ts`: add the chain to `GAS_COMPARISON_MULTIPLIER_BY_CHAIN`. Default is `1.0`; for chains where gas is sub-cent regardless of conditions (Tempo's constant `2e10` attodollars/gas), set to `0`. The `compareQuotes` function in `src/lib/util/dutch.ts` reads this multiplier when comparing RFQ vs Classic quotes.
- `src/lib/constants.ts`: add the chain to `V3_BLOCK_LENGTH_BY_CHAIN` (e.g., Tempo `60` = 30s wallclock at 500ms blocks).
- `src/core/order-factory/dutch/DutchV3OrderFactory.ts`: for chains where basefee is constant or non-wei, set `adjustmentPerGweiBaseFee = 0` on V3 inputs and outputs. **This is the actual lever** — these fields are on the swapper-signed `UnsignedV3DutchOrderInfo`, NOT on the cosigner data, so they must be set at order construction time, not by the cosigner. (This is Correction B — see below.)
- `src/core/quoters/rfq/RFQQuoter.ts`: ensure the protocol-version mapping advertises `UNISWAPX_V3` for the chain, not V2.
- Feature flag: gate the chain behind a `disable_uniswapx_<chain>` flag in the config-service registry (look for the existing `disable_uniswapx` flag for the pattern). Default-active = OFF until launch. Single runtime step to enable: set the parameter to `{"threshold": 0}`.

**Tests** to add per chain:
- `compareQuotes` zeros out gas adjustment when `chainId === <CHAIN>` (if multiplier is 0).
- API rejects native-sentinel inputs for the chain.
- `DutchV3OrderFactory` constructs valid orders for the chain with the right `adjustmentPerGweiBaseFee` value.
- Protocol-version mapping returns V3 for the chain.
- `WrapUnwrapOrder.test.ts` iterates `CHAINID_NUMBERS`; if the chain has no native, filter it out (mirror the existing Celo handling).

---

## 4. Common gotchas (corrections discovered the hard way)

### Correction A: V3 cosigner-amount invariants are the SAME direction as V2

If you're extending the parameterization-api or implementing a new RFQ branch: V3's `_updateWithCosignerAmounts` (in `x-contracts/src/reactors/V3DutchOrderReactor.sol`) enforces the same swapper-improvement direction as V2:

- `inputOverride ≤ baseInput.startAmount` (cosigner can only **reduce** input)
- `outputOverride ≥ baseOutput.startAmount` (cosigner can only **increase** output)

The original Tempo TDD claimed these were "opposite from V2." That was wrong. Mirror the V2 RFQ override-validation flow exactly.

### Correction B: V3 gas-adjustment fields live on the swapper-signed payload, NOT on cosigner data

`adjustmentPerGweiBaseFee` and `startingBaseFee` are fields on `UnsignedV3DutchOrderInfo` (the swapper-signed struct), not on `V3CosignerData`. The cosigner physically **cannot** zero them out at signing time — they're already in the signed payload.

The actual lever is on the **order construction side**: `DutchV3OrderFactory` in trading-api sets these values when the unsigned order is built. So per-chain "zero out the gas adjustment for chain X" lives in trading-api's factory, not in parameterization-api's cosigner.

The parameterization-api can still read the live `block.basefee` as a **tripwire** and refuse to cosign if the swapper-signed `startingBaseFee` diverges materially from the observed value (TODO; not implemented as of Tempo).

### Correction C: ChainId enums live in TWO places in parameterization-api

Both `lib/util/chains.ts` AND `lib/config/chains.ts` need the new chain. The latter gates inbound request validation via Joi; the former is consumed everywhere else. Forgetting the second one means the API rejects Tempo requests at validation even though the cosigner code knows about the chain.

### Correction D: Sub-second blocks need a chain-scoped retry floor

Step Functions Wait state granularity is whole seconds. A `0.5s` retry rounds to `0` → hot loop. Add a chain-scoped floor (`MIN_RETRY_WAIT_SECONDS_<CHAIN>`), not a global one — global floors tighten Arbitrum/Unichain unnecessarily.

### Correction E: Don't treat "stablecoin native" as wrapped-native

For chains with no native token, do **not** set `WRAPPED_NATIVE_CURRENCY[CHAIN] = <some stablecoin>`. That's a category error: there are usually multiple stablecoins, and picking one auto-rewrites silent `0x0` → that stablecoin even when the user wanted a different one. Instead, hard-reject native-sentinel addresses at the API boundary and force clients to specify a real ERC20.

### Correction F: Don't worry about state-creation gas overhead

Chains with elevated state-creation costs (Tempo: 12.5×) sound scary but are economically immaterial when basefee is sub-cent. 250K gas × `2e10` attodollars/gas = $0.005. Don't over-engineer pricing for this — let fillers absorb it.

---

## 5. Rollout plan template

**Phase 0 — alignment (3 days)**
- Identify launch fillers (1–2 PMMs).
- Decide canary stablecoin pairs.
- Confirm chain team is OK with our planned addresses + protocolFeeOwner.

**Phase 1 — contracts deploy (1 day)**
- Deploy `V3DutchOrderReactor` to mainnet via `x-contracts/script/DeployDutchV3.s.sol`.
- Deploy `OrderQuoter` lens.
- Verify on the chain's explorer. Record addresses.

**Phase 2 — SDK update + canary (1 day)**
- Replace zero-address placeholders in `uniswapx-sdk/src/constants.ts` with real reactor + quoter addresses.
- Cut `@uniswap/uniswapx-sdk` canary release (`x.y.z-<chain>.0`).

**Phase 3 — service deploys (1 week)**
- Pin trading-api / x-service / parameterization-api to the SDK canary in dev.
- Deploy parameterization-api → x-service → trading-api in that order.
- `disable_uniswapx_<chain>` flag stays ON throughout (= UniswapX OFF on the chain).
- Internal security review of any new cosigning logic.

**Phase 4 — closed canary (1 week)**
- Whitelist 1–2 PMM addresses via the existing exclusivity mechanism.
- Flip `disable_uniswapx_<chain>` to `false`.
- Real swaps at small notional ($100–$1k). Monitor:
  - Decay block math hits expected windows
  - Gas-adjustment net-zero where expected
  - Step Functions retry cadence within execution-history limits
  - `compareQuotes` selecting RFQ where expected
- Extend dashboards with chain-specific cuts.

**Phase 5 — open canary (1 week)**
- Remove filler whitelist; cap notional via min-order-size.

**Phase 6 — full launch**
- Remove notional cap.
- Schedule a 30-day post-launch review.

**Rollback**: `disable_uniswapx_<chain> = true` short-circuits routing to Classic-only on the chain. Order posting can be disabled in x-service via `SUPPORTED_CHAINS` redeploy. No on-chain rollback needed — unused reactors are inert.

---

## 6. Tempo case study (TRA2-12)

All work landed across the following PRs (each links back to Linear TRA2-12):

| Repo | PR |
|---|---|
| `x-contracts` | [Uniswap/UniswapX#367](https://github.com/Uniswap/UniswapX/pull/367) |
| `sdks/sdk-core` | [Uniswap/sdks#533](https://github.com/Uniswap/sdks/pull/533), [Uniswap/sdks#540](https://github.com/Uniswap/sdks/pull/540) |
| `sdks/uniswapx-sdk` | [Uniswap/sdks#577](https://github.com/Uniswap/sdks/pull/577) |
| `x-parameterization-api` | [Uniswap/uniswapx-parameterization-api#438](https://github.com/Uniswap/uniswapx-parameterization-api/pull/438) |
| `x-service` | [Uniswap/uniswapx-service#654](https://github.com/Uniswap/uniswapx-service/pull/654) |
| `b/packages/services/trading` | [Uniswap/backend#7813](https://github.com/Uniswap/backend/pull/7813) |

---

## 7. Avalanche / Robinhood quick-start

Before kicking off either, run the §0 questionnaire and §1 audit. Almost all the diff for the next chain will be additive (new entries in maps/enums) — the structural work in parameterization-api (V3 RFQ cosigning + per-chain decay block-length helpers) and trading-api (per-chain gas multiplier + native-sentinel rejection) is now done.

**Avalanche specifics worth pre-checking:**
- `block.number`: standard.
- `block.basefee`: dynamic (EIP-1559). No special factory tweak.
- Native: AVAX. WRAPPED_NATIVE_CURRENCY = WAVAX. Standard treatment.
- Permit2 deployment status — verify with `eth_getCode`.
- Block time ~2s — no sub-second floor needed.

**Robinhood specifics worth pre-checking** (likely a Robinhood Chain L2; verify):
- All §0 questions still apply; treat as an unknown chain until verified.
- Check whether it has a native token or follows Tempo's stablecoin-only model.

When either lands, file a follow-on Linear ticket and add a row to §6's case-study table.
