# Ink (chainId 57073) — DutchV3 rollout research

**Status:** 🟢 **Contracts deployed** — `V3DutchOrderReactor` at `0x000000007A1C8e570011EeDF86A2A35593013cBA` (the canonical post-4663 address, shared with Robinhood; owner + permit2 verified on-chain, source verified on Blockscout), `OrderQuoter` at canonical `0x00000000a3db63Df9078cBF3dF88B4CAdD5a7F58`. SDK/service wiring (Phases 2–4) pending.

Original audit assessment: 🟢 Ready to deploy — textbook OP-stack L2 (Kraken), no UniswapX coverage at the time. Every §0/§1 cell is standard; the only structural item is salt selection — see [Salt / bytecode note](#salt--bytecode-note).

**RPC probed:** `https://rpc-gel.inkonchain.com` (public). `eth_chainId` → `0xdef1` (= 57073) confirmed; `web3_clientVersion` → `op-reth/v2.4.1-rc.5-a9a8dad3`. Explorer: `https://explorer.inkonchain.com` (Blockscout; `/api` returns HTTP 200, so `forge verify-contract --verifier blockscout` is available).

All probes below were run live on **2026-08-03** against block ~52,274,600.

## Existing UniswapX coverage on chainId 57073

From `uniswapx-sdk/src/constants.ts` — **zero coverage, cleanest possible greenfield diff**:

| Mapping | Entry for 57073 |
|---|---|
| `PERMIT2_MAPPING` | **absent** — Ink is not in `NETWORKS_WITH_SAME_ADDRESS` (only 1/5/137/8453/130 are). Permit2 *is* deployed at the canonical address on-chain (verified); the SDK map needs an explicit entry. |
| `UNISWAPX_ORDER_QUOTER_MAPPING` | **absent** — needs explicit entry once OrderQuoter is deployed |
| `REACTOR_ADDRESS_MAPPING[57073]` | **absent** — no reactors of any type live on Ink |
| `EXCLUSIVE_FILLER_VALIDATION_MAPPING` | **absent** — needs explicit entry |
| `UNISWAPX_V4_*`, `HYBRID_RESOLVER_ADDRESS_MAPPING` | absent (Ink not in V4 scope) |

**`@uniswap/sdk-core` is already done — Phase 1 reduces to the x-contracts deploy.** `ChainId.INK = 57073` (`chains.ts:40`), in `SUPPORTED_CHAINS` (`:133`), `AVERAGE_BLOCK_TIMES_SECONDS[ChainId.INK] = 1` (`:71`), a full `INK_ADDRESSES` block wired into `CHAIN_TO_ADDRESSES_MAP` (`addresses.ts:550`, `:601`), and `WETH9[57073]` (`entities/weth9.ts:40`). No sdk-core PR needed.

## §0 Pre-integration questionnaire

| Question | Ink answer |
|---|---|
| **chainId** | `57073` (`eth_chainId` → `0xdef1`) |
| **RPC + explorer** | `https://rpc-gel.inkonchain.com` (public) / `https://explorer.inkonchain.com` (Blockscout, verification API live) |
| **Block time (target)** | **1s exactly** — verified across 4 consecutive blocks (52274616→52274619, timestamps +1s each, all non-empty). Matches sdk-core's `AVERAGE_BLOCK_TIMES_SECONDS[ChainId.INK] = 1`. No on-demand/idle gaps (unlike Robinhood) — Ink produces blocks continuously. |
| **Finality model** | OP-stack L2 (Kraken-operated). Sequencer soft-confirms sub-second; L1 finality ~15min via batcher → Ethereum. Same trust model as Base/Optimism for filler purposes. |
| **`block.number` semantics** | Standard EVM monotonic counter (probed +1/block, contiguous) — **no `BlockNumberish.sol` branch needed**. Ink is OP-stack, not Orbit; the existing 42161/4663 ArbSys gating does not apply and the standard `_getBlockNumber()` path is taken. |
| **`block.basefee` semantics** | Standard EIP-1559 **real wei**, genuinely dynamic. Probed 261 / 254 / 252 / 253 / 272 / 623 wei across samples spanning ~20M blocks. Magnitude is tiny but the value moves → **do NOT zero `adjustmentPerGweiBaseFee`**. |
| **`block.timestamp` semantics** | Standard Unix seconds, monotonic +1s/block (1785773027 → 1785773030 across 4 blocks). Deadline math safe. |
| **Native gas token** | ETH. WETH at the canonical OP-stack predeploy `0x4200000000000000000000000000000000000006` (2,865 bytes, `symbol()` → `"WETH"` verified live). `NATIVE` sentinel `0x0` is fully supported. |
| **`CALLVALUE` / `BALANCE` / `SELFBALANCE`** | Standard — OP-stack EVM-equivalent. `payable` modifiers, the `BaseReactor` leftover-balance refund branch, and sample-executor native sweeps all behave as on mainnet. |
| **State creation costs** | Standard OP-stack gas schedule. No Tempo-style multiplier; forge's default 130% gas estimate is sufficient (no `gasEstimateMultiplier` entry in salts.json). |
| **Permit2 at canonical address?** | ✅ Yes — 9,152 bytes at `0x000000000022D473030F116dDEE9F6B43aC78BA3`; `DOMAIN_SEPARATOR()` → `0x254e691db5cba516b5990791da994b69ebbe74e68e5bafb718970a1297e1be68` (non-zero, ABI-compatible). |
| **Arachnid CREATE2 factory?** | ✅ Yes — 69 bytes at `0x4e59b44847b379578588920cA78FbF26c0B4956C`. Deterministic vanity addresses available. |
| **Sequencer / private mempool / pre-confs** | Single OP-stack sequencer (Kraken-operated), public mempool, no pre-confs beyond soft-confirmations. RFQ `ExclusivityLib` works exactly as on Base/Optimism/Soneium. |
| **EIP-1559 / typed tx support** | ✅ `baseFeePerGas` populated on every block, dynamic, real wei. Cosigner can read it as a tripwire. |
| **Routing surfaces** | Full stack live and code-verified on-chain: v2 factory `0xfe57a6ba1951f69ae2ed4abe23e0f095df500c04` / router `0xb3fb126acdd5adca2f50ac644a7a2303745f18b4`, v3 factory `0x640887a9ba3a9c53ed27d0f7e8246a4f933f3424`, SwapRouter02 `0x177778f19e89dd1012bdbe603f144088a95c4b53`, v4 PoolManager `0x360e68faccca8ca495c1b759fd9eee466db9fb32` (24,009 bytes), UniversalRouter v2.0 `0x112908dac86e20e7241b0927479ea3bf935d1fa0` (19,499 bytes) and v2.1.1/v2.2.0 (aliased) `0x28bd21bb4ea4fda370d8d7544992038375d8d456` (22,177 bytes). Multicall3 at canonical `0xcA11bde05977b3631167028862bE2a173976CA11` (3,808 bytes). Existing `UniversalRouterExecutor` / `SwapRouter02Executor` sample executors are usable unmodified. |
| **protocolFeeOwner** | `0x2bad8182c09f50c8318d769245bea52c32be46cd` — from `PoolManager.owner()` at `0x360e68fa…fb32`, verified live 2026-08-03. Happens to equal the canonical Arbitrum One owner. **No code at that address on Ink** → the deploy script's EOA warning will fire (non-blocking; same as Soneium/XLayer/Robinhood). |

## §1 EVM compatibility audit

| Behavior | Ink | Action |
|---|---|---|
| `block.number` monotonic & contiguous | ✅ probed +1 per block | none — standard `_getBlockNumber()` path |
| `block.basefee` real wei value | ✅ dynamic EIP-1559 (252–623 wei observed) | none — leave `adjustmentPerGweiBaseFee` at default |
| `block.timestamp` Unix seconds, monotonic | ✅ +1s/block | none |
| `msg.value` reflects sent ETH | ✅ OP-stack equivalent | none — orders may use the NATIVE sentinel |
| `address(this).balance` reflects ETH balance | ✅ | none — sample-executor native sweeps are valid |
| Permit2 at canonical address | ✅ verified + functional | add explicit `PERMIT2_MAPPING[57073]` |
| Arachnid CREATE2 deployer present | ✅ 69 bytes | none |
| EIP-1559 fields populated | ✅ | cosigner can use live `baseFeePerGas` as a tripwire |
| Canonical OrderQuoter address free | ✅ no code at `0x00000000a3db63Df9078cBF3dF88B4CAdD5a7F58` | deploy via `script/DeployOrderQuoter.s.sol` (salt still valid — see below) |

**No non-standard cells.** No `BlockNumberish.sol` fork, no `adjustmentPerGweiBaseFee = 0`, no API-boundary native-sentinel rejection, no sub-second retry floor (1s blocks ≥ Step Functions Wait granularity — Correction D does not apply).

## Salt / bytecode note

Ink's `PoolManager.owner()` is the canonical `0x2bad…46cd`, which historically meant "reuse Tempo's canonical salt and converge on `0x000000005aF66799D1a6317714D66800f9CA1406`". **That no longer holds.** The Robinhood rollout added chainid 4663 to the ArbSys branch in `src/base/BlockNumberish.sol`, which changed `V3DutchOrderReactor`'s `creationCode`, retiring the canonical salt for every chain deployed after that change.

Verified 2026-08-03 against a fresh `./scripts/build.sh` (macOS, forge `v1.4.4`, solc `0.8.30`, optimizer 1M runs):

- initcode hash for (PERMIT2, `0x2bad…46cd`): `0xa0bb393cdda0ac5efd502d4a360857a57b9236290eea382de95c843d90a2bd55` — **stable across a rebuild**, so the toolchain is reproducible on this host.
- Canonical Tempo salt `0x…e931b28b35b132822db301c0` under that initcode derives `0xb90EBE0d009771FA53a0921Af7a7431934f144BC` — no zero prefix, not the canonical address. Confirms the salt is dead.
- **`OrderQuoter` is unaffected**: its initcode hash is `0xd374a07131d8844fa992cd8d5bb4f06a5f461e1f4f22fe507efa45f8c3648122` and the committed `SALT` in `script/DeployOrderQuoter.s.sol` still derives `0x00000000a3db63Df9078cBF3dF88B4CAdD5a7F58` exactly. OrderQuoter doesn't inherit `BlockNumberish`, so the canonical cross-chain quoter address holds on Ink.

⇒ Parity with the 17 **pre-4663** chains is not achievable and should not be expected. Parity with the **post-4663** chains that share the canonical owner *is* — see below. **Deploy from macOS only** (see the toolchain-reproducibility block in `script/DeployDutchV3.s.sol`).

**Salt: reuse, do not mine.** Ink's owner is the canonical `0x2bad…46cd` and its bytecode is the current post-4663 build — identical to Robinhood's on both counts. So Robinhood's salt applies verbatim and Ink converges on the same reactor address:

| | |
|---|---|
| `V3_REACTOR_SALT` | `0x00000000000000000000000000000000000000001585866b75f2b774c6520080` (mined for Robinhood 2026-06-12; 4 leading + 5 total zero bytes) |
| `V3_REACTOR_EXPECTED` | `0x000000007A1C8e570011EeDF86A2A35593013cBA` |

Verified 2026-08-05: that salt under Ink's initcode hash `0xa0bb393c…` derives `0x000000007A1C…3cBA` exactly, and the address was free on Ink before deploy.

The deployed **runtime** differs from Robinhood's by exactly 3 bytes (two runs at offsets `0xae5` and `0xaea`) — the `BlockNumberish` immutable function pointer, which the constructor sets per `block.chainid`: Robinhood resolves to `ArbSys.arbBlockNumber()`, Ink to `block.number`. CREATE2 hashes the *initcode*, not the runtime, so the address is unaffected. This byte-diff is also positive confirmation that the chain gating took effect on each chain.

### Pre-broadcast simulation (2026-08-03, wallet-free, live Ink RPC)

Both scripts were run without `--broadcast` against the live chain, which exercises the in-script `predicted == EXPECTED` assertion plus the Permit2 / Arachnid / chain-id-pin requires:

- `DeployDutchV3.s.sol` → **SIMULATION COMPLETE**, `Predicted == Expected`. Estimated 5,272,590 gas at 0.000002632 gwei ≈ **0.0000000139 ETH**. The `MIN_BALANCE_WEI` default of 0.05 ETH is ~6 orders of magnitude more than needed; it's a liveness floor, not a cost estimate.
- `DeployOrderQuoter.s.sol` → **SIMULATION COMPLETE** at canonical `0x00000000a3db63Df9078cBF3dF88B4CAdD5a7F58`.

Gas cost is negligible, so `MIN_BALANCE_WEI` (default 0.05 ETH) functions purely as a liveness floor here — six orders of magnitude above the actual requirement. Lower it via the env var rather than over-funding the deployer.

**Verification flag caveat:** the Tempo example in `script/DeployOrderQuoter.s.sol`'s header uses `--verify`, which resolves to Etherscan and fails on Ink (`{"message":"Unknown API v2 action"}` — harmless noise during simulation, but it will not verify). Use Blockscout explicitly instead:

```bash
forge verify-contract <addr> <Contract> \
    --chain-id 57073 \
    --verifier blockscout \
    --verifier-url https://explorer.inkonchain.com/api
```

## Deploy parameters

| Parameter | Value | Rationale |
|---|---|---|
| `FOUNDRY_REACTOR_OWNER` | `0x2bad8182c09f50c8318d769245bea52c32be46cd` | `PoolManager.owner()` at `0x360e68fa…fb32`, verified live 2026-08-03. EOA on Ink → non-blocking WARN. |
| `V3_REACTOR_SALT` | `0x…1585866b75f2b774c6520080` — the post-4663 `canonical` pair, reused not mined | Same owner + same bytecode as Robinhood ⇒ address parity. |
| `V3_REACTOR_EXPECTED` | `0x000000007A1C8e570011EeDF86A2A35593013cBA` | Shared with Robinhood. |
| Deploy route | `./scripts/deploy-v3-multichain.sh` — a `57073` default is in both wrappers' `default_rpc()`, so no `RPC_57073` override is needed (and note an `RPC_57073` in your shell or `.env` will silently take precedence) | Every precondition except the deployer-balance gate was verified live 2026-08-03: RPC/chainId, salt present, `PoolManager.owner()` match, target empty, Permit2 functional, Arachnid present, simulation. The owner-EOA warning fires and is non-blocking. |
| Lens | OrderQuoter at canonical `0x00000000a3db63Df9078cBF3dF88B4CAdD5a7F58` via `script/DeployOrderQuoter.s.sol` / `scripts/deploy-quoter-multichain.sh` | Salt verified still valid on current bytecode. |
| Deployer gas funding | ETH on Ink (bridge via `https://inkonchain.com/bridge` or a supported third-party bridge) | `MIN_BALANCE_WEI` default is 0.05 ETH; actual cost is negligible at ~260 wei basefee. |
| `gasEstimateMultiplier` | none (forge default 130%) | Standard OP-stack code-deposit pricing. |
| `V3_BLOCK_LENGTH_BY_CHAIN[57073]` (trading-api) | `30` | `ceil(30s / 1s)` — 30s wallclock decay at 1s blocks. |
| `V3_BLOCK_BUFFER` (parameterization-api) | `4` (default) | 1s blocks; mirror Unichain/XLayer (also 1s). |
| `getBlockTimeSecs(57073)` (parameterization-api) | `1` | Matches sdk-core. |
| `BLOCK_TIME_MS_BY_CHAIN[57073]` (x-service) | `1000` | — |
| `AVERAGE_BLOCK_TIME(57073)` (x-service) | `1` second | — |
| `MIN_RETRY_WAIT_SECONDS_<CHAIN>` floor | **not needed** | 1s blocks are not sub-second; Correction D doesn't apply. |
| `OLDEST_BLOCK_BY_CHAIN[57073]` (x-service) | ~`52274600` (block at 2026-08-03) | Refresh to a recent block at deploy time. |
| `PRIORITY_ORDER_TARGET_BLOCK_BUFFER[57073]`, `HYBRID_…[57073]` | `0` with comment | No Priority/Hybrid reactor at launch; `OffChainUniswapXOrderValidator.validateReactorAddress` rejects those order types upstream because the SDK has no mapping entry. |
| `GAS_COMPARISON_MULTIPLIER_BY_CHAIN[57073]` (trading-api) | `1.0` (default) | Real dynamic wei basefee. Low magnitude is not a reason to zero it (Correction: only Tempo-style non-wei/constant basefee qualifies). |
| `WRAPPED_NATIVE_CURRENCY[57073]` (trading-api) | `0x4200000000000000000000000000000000000006` | Canonical OP-stack WETH predeploy, `symbol()` verified live. Native ETH is real — do **not** reject the native sentinel (Correction E doesn't apply). |
| `adjustmentPerGweiBaseFee` (DutchV3OrderFactory) | default (non-zero path) | Standard wei basefee. |
| Trading-api `CHAIN_INFO_MAP[57073]` | `blockTimeMs: 1000`, `pollingIntervalMs: 250`, `orderTypeOverrides[DUTCH_V3].deadlineBufferSecs` tuned like other 1s OP-stack chains (Unichain) | — |
| Canary pairs | ETH/WETH ↔ **USD₮0** `0x0200C29006150606B650577BBE7B6248F58470c1` (6 dec, `symbol()` → `USD₮0`) or **USDC.e** `0xF1815bd50389c46847f0Bda824eC8da914045D14` (6 dec, verified live) | Ink's two primary stablecoins. Both symbol+decimals probed on-chain 2026-08-03. |

## Notes / launch caveats

- **Classic routing already exists** — `b/packages/services/uniroute/src/stores/chain/hardcoded/chains/Ink.ts` has Ink fully wired (v2 + v3 + v4 + UR v2.0/v2.1.1/v2.2.0, token-fee detector, multicall), and `packages/lib/data-api/src/types/chain.ts:34` has `INK = 57073`. So `compareQuotes` has a real Classic leg. **Trading-api itself has no `57073` reference yet** (`packages/services/trading/src` — grep clean), so §3.6 is a genuine greenfield add there.
- **`multicallAddress` differs from canonical.** sdk-core `INK_ADDRESSES` and uniroute both use `0xa0fcec583aee6176527c07b198e5561722332014`, not the canonical Multicall3 `0xcA11…CA11` (which is *also* deployed, 3,808 bytes). Not a UniswapX concern, but don't "fix" one to match the other without checking why they diverge.
- **No `disable_uniswapx_ink` flag exists yet** — create one in the config-service registry, default-active = OFF until launch.
- **`sdk-core` needs no PR** (see above) — the single biggest saving vs. a typical greenfield chain.
- **Idle-chain decay is a non-issue** here (unlike Robinhood): Ink produces a block every second regardless of demand, so block-driven V3 decay tracks wallclock 1:1.
