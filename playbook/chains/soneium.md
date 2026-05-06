# Soneium (chainId 1868) — DutchV3 rollout research

**Status:** 🟢 Ready to deploy DutchV3 — clean greenfield OP-stack L2, no UniswapX coverage yet.

**RPC probed:** `https://rpc.soneium.org` (universe `RPCType.Default`).
QuickNode endpoint `getQuicknodeEndpointUrl(UniverseChainId.Soneium)` is the
universe-canonical Public/Interface RPC; the public endpoint is sufficient
for §0 + §1 probes. `eth_chainId` returned `0x74c` (= 1868) — confirmed.

## Existing UniswapX coverage on chainId 1868

From `uniswapx-sdk/src/constants.ts`:

| Mapping | Entry for 1868 |
|---|---|
| `PERMIT2_MAPPING` | **absent** — Soneium is NOT in `NETWORKS_WITH_SAME_ADDRESS` (only 1/5/137 are). Permit2 is deployed on-chain at the canonical address (verified) but the SDK map needs an explicit entry. |
| `UNISWAPX_ORDER_QUOTER_MAPPING` | **absent** (same reason — needs explicit entry once OrderQuoter is deployed) |
| `REACTOR_ADDRESS_MAPPING[1868]` | **absent** — no reactors of any type live on Soneium |
| `EXCLUSIVE_FILLER_VALIDATION_MAPPING` | **absent** — needs explicit entry |
| `UNISWAPX_V4_*` | absent (Soneium not in scope for V4 rollout) |
| `HYBRID_RESOLVER_ADDRESS_MAPPING` | absent |

Soneium is in `@uniswap/sdk-core`'s `ChainId` enum (`ChainId.SONEIUM = 1868`,
`sdks/sdk-core/src/chains.ts:32` + `SUPPORTED_CHAINS` line 67) but has no
addresses block in `addresses.ts` and no entries in any `uniswapx-sdk`
mapping. **Greenfield rollout** — every mapping needs a fresh `[1868]` key.

## §0 Pre-integration questionnaire

| Question | Soneium answer |
|---|---|
| **chainId** | `1868` (`eth_chainId` → `0x74c`) |
| **RPC + explorer** | `https://rpc.soneium.org` (public) / `https://soneium.blockscout.com/` |
| **Block time (target)** | ~2s — confirmed via 3 consecutive blocks (22481763→22481765 spans 4s, i.e. 2s/block); matches `SONEIUM_CHAIN_INFO.blockTimeMs = 2000` |
| **Finality model** | OP-stack L2 by Sony; sequencer soft-confirmations sub-second, L1 finality after ~15min via batcher → Ethereum |
| **`block.number` semantics** | Standard EVM monotonic counter (OP-stack inherits) — no `BlockNumberish.sol` branch needed |
| **`block.basefee` semantics** | Standard EIP-1559 wei. Probed `baseFeePerGas = 0x132` (306 wei ≈ 3e-7 gwei) — dynamic, real wei units. **Do NOT** zero `adjustmentPerGweiBaseFee` (basefee is genuine EIP-1559, just very low) |
| **`block.timestamp` semantics** | Standard Unix seconds (probed: 1778098277 → 1778098281 monotonic +4s across 2 blocks) |
| **Native gas token** | ETH (`SONEIUM_CHAIN_INFO.nativeCurrency.symbol = 'ETH'`); WETH at canonical OP-stack predeploy `0x4200000000000000000000000000000000000006`. NATIVE sentinel `0x0` is supported |
| **`CALLVALUE` / `BALANCE` / `SELFBALANCE` opcodes** | Standard — OP-stack EVM-equivalent. `payable` modifiers, leftover-balance refund branches, and sample-executor native sweeps all work as on mainnet |
| **State creation costs** | Standard OP-stack gas schedule; no Tempo-style multiplier |
| **Permit2 at canonical address?** | ✅ Yes — `eth_getCode 0x000000000022D473030F116dDEE9F6B43aC78BA3` returned 18 306-byte runtime |
| **Arachnid CREATE2 factory?** | ✅ Yes — `eth_getCode 0x4e59b44847b379578588920cA78FbF26c0B4956C` returned 140-byte runtime; deterministic vanity addresses available |
| **Sequencer / private mempool / pre-confs** | Single Optimism-style sequencer (Sony-operated), public mempool, no pre-confs distinct from soft-confirmations. RFQ `ExclusivityLib` works as on Base/Optimism |
| **EIP-1559 / typed tx support** | ✅ Yes — basefee field populated, dynamic, in real wei |
| **Routing surfaces** | UniversalRouter v2.0 + v2.1.1 supported (`SONEIUM_CHAIN_INFO.supportedURVersions`); v4 supported (`supportsV4: true`). Existing `UniversalRouterExecutor` and `SwapRouter02Executor` sample executors usable |

## §1 EVM compatibility audit

| Behavior | Soneium | Action |
|---|---|---|
| `block.number` monotonic & contiguous | ✅ probed +1 per block | none |
| `block.basefee` real wei | ✅ dynamic EIP-1559 (probed 306 wei but live and varying) | none — leave `adjustmentPerGweiBaseFee` at default |
| `block.timestamp` Unix seconds, monotonic | ✅ +2s/block | none |
| `msg.value` reflects sent ETH | ✅ (OP-stack equivalent) | none — orders may use NATIVE sentinel |
| `address(this).balance` reflects ETH balance | ✅ | none — sample executors' native-sweep paths are valid |
| Permit2 at canonical address | ✅ verified via `eth_getCode` | add explicit `PERMIT2_MAPPING[1868]` entry pointing to canonical address |
| EIP-1559 fields populated | ✅ | cosigner can read live `baseFeePerGas` as a tripwire |

No non-standard cells — Soneium is a textbook OP-stack chain from UniswapX's perspective. No `BlockNumberish.sol` fork, no `adjustmentPerGweiBaseFee = 0`, no API-boundary native rejection, no sub-second retry floor (2s blocks ≥ Step Functions Wait granularity, no floor needed).

## Deploy parameters

- **`FOUNDRY_REACTOR_OWNER`**: `0x2bad8182c09f50c8318d769245bea52c32be46cd` (Arbitrum One protocolFeeOwner; reuse unless governance specifies otherwise).
- **OrderQuoter**: not yet deployed — deploy fresh via `script/DeployDutchV3.s.sol` (or dedicated lens script). Arachnid CREATE2 factory present, so deterministic address `0x54539967a06Fc0E3C3ED0ee320Eb67362D13C5fF` (canonical) is achievable.
- **`V3_BLOCK_LENGTH_BY_CHAIN[1868]`**: `ceil(30 / 2) = 15` blocks (30s wallclock decay at 2s blocks).
- **`V3_BLOCK_BUFFER` (parameterization-api)**: `4` (default — 2s blocks, no special tuning).
- **`BLOCK_TIME_MS_BY_CHAIN[1868]` (x-service)**: `2000`.
- **`AVERAGE_BLOCK_TIME(1868)` (x-service)**: `2` seconds.
- **`MIN_RETRY_WAIT_SECONDS_<CHAIN>`**: not needed (block time = 2s, not sub-second).
- **`PRIORITY_ORDER_TARGET_BLOCK_BUFFER[1868]`**: set to `0` with comment (no Priority reactor; `OffChainUniswapXOrderValidator.validateReactorAddress` rejects priority orders for chains absent from SDK mapping).
- **`HYBRID_ORDER_TARGET_BLOCK_BUFFER[1868]`**: set to `0` with comment (no hybrid reactor).
- **`GAS_COMPARISON_MULTIPLIER_BY_CHAIN[1868]` (trading-api)**: `1.0` (standard EIP-1559 chain; basefee is real wei despite very low magnitude).
- **Trading-api `CHAIN_INFO_MAP[1868]`**: `blockTimeMs: 2000`, `pollingIntervalMs: 250` (matches universe `tradingApiPollingIntervalMs`), tune `orderTypeOverrides[OrderType.DUTCH_V3].deadlineBufferSecs` like other 2s OP-stack chains.
- **`WRAPPED_NATIVE_CURRENCY[1868]`**: `0x4200000000000000000000000000000000000006` (canonical OP-stack WETH predeploy; matches `SONEIUM_CHAIN_INFO.wrappedNativeCurrency.address`).

## Notes

- **Greenfield rollout.** Unlike Unichain (Priority already live) or Tempo (custom constraints), Soneium has zero UniswapX presence — every mapping needs a fresh `[1868]` entry. Cleanest possible diff: pure additions, no existing-entry mutations.
- Soneium is NOT in `NETWORKS_WITH_SAME_ADDRESS` in `uniswapx-sdk/src/constants.ts` — explicit `PERMIT2_MAPPING[1868]`, `UNISWAPX_ORDER_QUOTER_MAPPING[1868]`, `EXCLUSIVE_FILLER_VALIDATION_MAPPING[1868]`, and `REACTOR_ADDRESS_MAPPING[1868]` entries all required. (Adding to `NETWORKS_WITH_SAME_ADDRESS` is an alternative but riskier — touches every map at once.)
- Sample executors (`UniversalRouterExecutor`, `SwapRouter02Executor`) work without modification; UR v2.0/v2.1.1 are both routable per universe config.
- Bridge-USDC liquidity: Soneium's primary stablecoin is `USDCE` (`0xbA9986D2381edf1DA03B0B9c1f8b00dc4AacC369`, 6 decimals, "Soneium Bridged USDC") per universe config — use for canary pairs alongside ETH/WETH.
- No `disable_uniswapx_soneium` flag exists yet; create one for the rollout (default-active = OFF until launch).
- `sdks/sdk-core/src/addresses.ts` has no `SONEIUM_ADDRESSES` block — needs adding (v3/v4/router contracts) before downstream repos can pin against `ChainId.SONEIUM`.
