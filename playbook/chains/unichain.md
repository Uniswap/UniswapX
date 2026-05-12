# Unichain (chainId 130) — DutchV3 rollout research

**Status:** 🟢 Ready to deploy DutchV3 — additive alongside the already-live Priority reactor.

**RPC probed:** `https://mainnet.unichain.org` (universe `RPCType.Default`).
QuickNode endpoint `getQuicknodeEndpointUrl(UniverseChainId.Unichain)` is the
universe-canonical Public/Interface RPC; the public endpoint is sufficient
for §0 + §1 probes.

## Existing UniswapX coverage on chainId 130

From `sdks/uniswapx-sdk/src/constants.ts`:

| Mapping | Entry for 130 |
|---|---|
| `PERMIT2_MAPPING` | inherited via `constructSameAddressMap` (Unichain is in `NETWORKS_WITH_SAME_ADDRESS`) → `0x000000000022d473030f116ddee9f6b43ac78ba3` |
| `UNISWAPX_ORDER_QUOTER_MAPPING` | `0xc6ef4C96Ee89e48Eff1C35545DBEED4Ad8dAC9D4` (same address as 1/10/8453/42161) |
| `REACTOR_ADDRESS_MAPPING[130]` | `Dutch=0x0`, `Dutch_V2=0x0`, `Relay=0x0`, **`Priority=0x00000006021a6Bce796be7ba509BBBA71e956e37`** |
| `EXCLUSIVE_FILLER_VALIDATION_MAPPING` | inherited via `constructSameAddressMap` → `0x8A66A74e15544db9688B68B06E116f5d19e5dF90` |
| `UNISWAPX_V4_ORDER_QUOTER_MAPPING` | `0x0` (no V4 on Unichain mainnet — Sepolia 1301 only) |
| `UNISWAPX_V4_TOKEN_TRANSFER_HOOK_MAPPING` | `0x0` (Sepolia only) |
| `HYBRID_RESOLVER_ADDRESS_MAPPING` | absent (Sepolia 1301 only) |

**Priority orders are already live.** Adding DutchV3 is purely additive: a
new `[OrderType.Dutch_V3]` key on the existing `REACTOR_ADDRESS_MAPPING[130]`
object. The existing Priority entry, OrderQuoter, Permit2, and exclusive-filler
validation address are all reused as-is. No reverse-mapping collision
(addresses are distinct).

## §0 Pre-integration questionnaire

| Question | Unichain answer |
|---|---|
| **chainId** | `130` |
| **RPC + explorer** | `https://mainnet.unichain.org` (public) / `https://uniscan.xyz` |
| **Block time (target)** | ~1s — confirmed via 3 consecutive blocks (47349878→47349880 spans 2s, i.e. 1s/block); subblockTime 200ms per universe `unichain.ts` |
| **Finality model** | OP-stack L2; sequencer soft-confirmations sub-second, L1 finality after ~15min via batcher → Ethereum |
| **`block.number` semantics** | Standard EVM monotonic counter (OP-stack inherits) — no `BlockNumberish.sol` branch needed |
| **`block.basefee` semantics** | Standard EIP-1559 wei. Probed `baseFeePerGas = 0x7a120` (500 000 wei = 0.0005 gwei) — dynamic, real units. **Do NOT** zero `adjustmentPerGweiBaseFee` |
| **`block.timestamp` semantics** | Standard Unix seconds (probed: 1778098237 → 1778098239 monotonic +2s) |
| **Native gas token** | ETH (`UNICHAIN_CHAIN_INFO.nativeCurrency.symbol = 'ETH'`); WETH at canonical OP-stack address `0x4200000000000000000000000000000000000006`. NATIVE sentinel `0x0` is supported |
| **`CALLVALUE` / `BALANCE` / `SELFBALANCE` opcodes** | Standard — OP-stack EVM-equivalent. `payable` modifiers, leftover-balance refund branches, and sample-executor native sweeps all work as on mainnet |
| **State creation costs** | Standard OP-stack gas schedule; no Tempo-style multiplier |
| **Permit2 at canonical address?** | ✅ Yes — `eth_getCode 0x000000000022D473030F116dDEE9F6B43aC78BA3` returned 18 306-byte runtime |
| **Arachnid CREATE2 factory?** | ✅ Yes — `eth_getCode 0x4e59b44847b379578588920cA78FbF26c0B4956C` returned 140-byte runtime; deterministic vanity addresses available |
| **Sequencer / private mempool / pre-confs** | Single Optimism-style sequencer, public mempool, no pre-confs distinct from soft-confirmations. RFQ `ExclusivityLib` works as on Base/Optimism |
| **EIP-1559 / typed tx support** | ✅ Yes — basefee field populated and dynamic |
| **Routing surfaces** | UniversalRouter v2.0 + v2.1.1 supported (`UNICHAIN_CHAIN_INFO.supportedURVersions`); v4 supported (`supportsV4: true`). Existing `UniversalRouterExecutor` and `SwapRouter02Executor` sample executors usable |

## §1 EVM compatibility audit

| Behavior | Unichain | Action |
|---|---|---|
| `block.number` monotonic & contiguous | ✅ | none |
| `block.basefee` real wei | ✅ dynamic EIP-1559 (probed 0.0005 gwei but live and varying) | none — leave `adjustmentPerGweiBaseFee` at default |
| `block.timestamp` Unix seconds, monotonic | ✅ | none |
| `msg.value` reflects sent ETH | ✅ | none — orders may use NATIVE sentinel |
| `address(this).balance` reflects ETH balance | ✅ | none — sample executors' native-sweep paths are valid |
| Permit2 at canonical address | ✅ | reuse existing `PERMIT2_MAPPING` entry |
| EIP-1559 fields populated | ✅ | cosigner can read live `baseFeePerGas` as a tripwire |

No non-standard cells — Unichain is a textbook OP-stack chain from UniswapX's perspective. No `BlockNumberish.sol` fork, no `adjustmentPerGweiBaseFee = 0`, no API-boundary native rejection, no sub-second retry floor (1s blocks ≥ Step Functions Wait granularity, no floor needed beyond defaults).

## Deploy parameters

- **`FOUNDRY_REACTOR_OWNER`**: `0x2bad8182c09f50c8318d769245bea52c32be46cd` (Arbitrum One protocolFeeOwner; reuse unless governance specifies otherwise).
- **OrderQuoter**: already deployed at `0xc6ef4C96Ee89e48Eff1C35545DBEED4Ad8dAC9D4` — no redeploy needed for V3.
- **`V3_BLOCK_LENGTH_BY_CHAIN[130]`**: `ceil(30 / 1) = 30` blocks (30s wallclock decay at 1s blocks).
- **`V3_BLOCK_BUFFER` (parameterization-api)**: `4` (default — fast blocks but not sub-second; no special tuning).
- **`BLOCK_TIME_MS_BY_CHAIN[130]` (x-service)**: `1000`.
- **`AVERAGE_BLOCK_TIME(130)` (x-service)**: `1` second.
- **`MIN_RETRY_WAIT_SECONDS_<CHAIN>`**: not needed (block time = 1s, not sub-second).
- **`PRIORITY_ORDER_TARGET_BLOCK_BUFFER[130]`**: already wired (Priority is live); leave as-is.
- **`HYBRID_ORDER_TARGET_BLOCK_BUFFER[130]`**: set to `0` with explanatory comment (no hybrid reactor).
- **`GAS_COMPARISON_MULTIPLIER_BY_CHAIN[130]` (trading-api)**: `1.0` (standard EIP-1559 chain).
- **Trading-api `CHAIN_INFO_MAP[130]`**: `blockTimeMs: 1000`, `pollingIntervalMs: 150` (matches universe `tradingApiPollingIntervalMs`), tune `orderTypeOverrides[OrderType.DUTCH_V3].deadlineBufferSecs` like Arbitrum.
- **`WRAPPED_NATIVE_CURRENCY[130]`**: `0x4200000000000000000000000000000000000006` (WETH); already populated for Priority — reused.

## Notes

- **DutchV3 is strictly additive on Unichain.** The only `REACTOR_ADDRESS_MAPPING[130]` mutation is adding `[OrderType.Dutch_V3]: <new reactor>`. The existing Priority entry, all other shared mappings (Permit2, OrderQuoter, ExclusiveFillerValidation), and the live Priority order flow are untouched.
- `OffChainUniswapXOrderValidator.validateReactorAddress` uses the SDK mapping — once V3 lands the validator accepts both `Priority` and `Dutch_V3` reactors for chainId 130 in parallel; no risk of crosstalk.
- Unichain is in `NETWORKS_WITH_SAME_ADDRESS` already, so no `PERMIT2_MAPPING` change is needed at all (deploy via Arachnid CREATE2 factory at the canonical address — verified present).
- Sample executors (`UniversalRouterExecutor`, `SwapRouter02Executor`) work without modification; UR v2.0/v2.1.1 are both routable per universe config.
- Dashboards already exist for chainId 130 (Priority); extend with V3 cuts during Phase 4 canary.
- No `disable_uniswapx_unichain` flag exists yet (Priority shipped without one); for V3 rollout, gate behind a fresh `disable_uniswapx_v3_unichain` feature flag distinct from the existing Priority path so each order type can be toggled independently.
