# Polygon PoS — DutchV3 rollout research

Per `../NEW_CHAIN.md` §0 + §1. Polygon is a long-running EVM L1 (Heimdall+Bor PoS), already on Uniswap front-end with Dutch V1 (classic) live; this scratchpad covers what's needed to extend to **DutchV3**.

## §0 Pre-integration questionnaire

| Question | Polygon answer |
|---|---|
| **chainId** | `137` |
| **RPC + explorer URLs** | Public: `https://polygon-rpc.com` (rate-limited; returned `tenant disabled` during this probe). Working: `https://polygon.drpc.org`. Universe also wires Quicknode + Infura. Explorer: `https://polygonscan.com/` |
| **Block time (target)** | ~2s. Probed head blocks 86490625/626/627 → timestamps 1778098301/303/305 (exactly 2s deltas) |
| **Finality model** | Heimdall checkpoints to Ethereum every ~30 min for hard finality. Bor produces blocks via PoS validator set; **occasional reorgs** of a few blocks happen — fillers should wait several confirmations (recommend ≥ 5 blocks ≈ 10s) before treating fills as final |
| **`block.number` semantics** | Standard EVM monotonic counter. No `BlockNumberish.sol` branch needed |
| **`block.basefee` semantics** | Real wei, dynamic EIP-1559. Probed `baseFeePerGas` ≈ 99–102 gwei across consecutive blocks (variance confirms it's live, not constant). Standard gas-adjustment math applies; **do not** zero `adjustmentPerGweiBaseFee` |
| **`block.timestamp` semantics** | Standard Unix seconds, monotonic |
| **Native gas token** | POL (rebranded MATIC, same `0x...1010` precompile address). Native sentinel `address(0)` is supported; `WRAPPED_NATIVE_CURRENCY[137] = WPOL = 0x0d500b1d8e8ef31e21c99d1db9a6444d3adf1270` |
| **`CALLVALUE` / `BALANCE` / `SELFBALANCE` opcodes** | Standard. Native sweeps in sample executors work. Note: native POL balance is exposed at the `0x...1010` precompile (Polygon-specific quirk for ERC20-style POL transfers), but `msg.value` and `address(this).balance` behave standardly for ETH-mechanism callers |
| **State creation costs** | Standard EVM (20K gas/SSTORE non-zero) |
| **Permit2 at canonical address?** | ✅ Yes. `eth_getCode` at `0x000000000022D473030F116dDEE9F6B43aC78BA3` returned 18306 bytes |
| **Sequencer / private mempool / pre-confs** | Decentralized PoS validators (Bor). Public mempool. No sequencer/pre-confs. Standard `ExclusivityLib` semantics — no extra protection needed |
| **EIP-1559 / typed tx support** | Yes. `baseFeePerGas` populated and dynamic; type-2 txs supported |
| **Routing surfaces (UniversalRouter, etc.)** | UniversalRouter v2.0 + v2.1.1 supported (per universe `polygon.ts`); v4 supported. Existing sample executors (`UniversalRouterExecutor`, `SwapRouter02Executor`) reusable as-is |

Arachnid CREATE2 deployer (`0x4e59b44847b379578588920cA78FbF26c0B4956C`) ✅ present (140-byte canonical bytecode).

## §1 EVM compatibility audit

| Behavior | Polygon | Action |
|---|---|---|
| `block.number` monotonic & contiguous | ✅ standard | none |
| `block.basefee` real wei value | ✅ dynamic EIP-1559 (~100 gwei observed) | none — keep default `adjustmentPerGweiBaseFee` |
| `block.timestamp` seconds since epoch, monotonic | ✅ standard | none |
| `msg.value` (`CALLVALUE`) reflects sent native | ✅ standard | none |
| `address(this).balance` (`BALANCE`/`SELFBALANCE`) | ✅ standard | none |
| Permit2 deployed at canonical address | ✅ verified | none — bind reactor to `0x000000000022D473030F116dDEE9F6B43aC78BA3` |
| EIP-1559 fields populated | ✅ | none — cosigner can read `baseFeePerGas` normally |

**No non-standard cells.** Polygon is a vanilla EVM chain from UniswapX's perspective.

## Existing UniswapX coverage (chainId 137)

From `uniswapx-sdk/src/constants.ts`:
- `PERMIT2_MAPPING[137]` → `0x000000000022d473030f116ddee9f6b43ac78ba3` (via `constructSameAddressMap`).
- `REACTOR_ADDRESS_MAPPING[137]` → inherits the same-address default: Dutch V1 = `0x6000da47483062A0D734Ba3dc7576Ce6A0B645C4`, Dutch V2 = `0x0` (not deployed), Relay = `0x0000000000A4e21E2597DCac987455c48b12edBF`.
- `UNISWAPX_ORDER_QUOTER_MAPPING[137]` → `0x54539967a06Fc0E3C3ED0ee320Eb67362D13C5fF`.
- `EXCLUSIVE_FILLER_VALIDATION_MAPPING[137]` → `0x8A66A74e15544db9688B68B06E116f5d19e5dF90`.
- **DutchV3 not deployed.** No entry in any `OrderType.Dutch_V3` slot.

Already in `@uniswap/sdk-core` `ChainId.POLYGON = 137` and in front-end `ORDERED_CHAINS`.

## Deploy parameters

- **`V3_BLOCK_LENGTH_BY_CHAIN[137]`**: `15` blocks = `ceil(30s / 2s)` for the standard `V3_DEFAULT_DECAY_DURATION_SECS = 30s` wallclock decay.
- **`V3_BLOCK_BUFFER`**: default `4` is fine (no sub-second blocks).
- **`BLOCK_TIME_MS_BY_CHAIN[137]`**: `2000` (matches universe `polygon.ts:62` `blockTimeMs: 2000`).
- **`AVERAGE_BLOCK_TIME(137)`**: `2` seconds.
- **`MIN_RETRY_WAIT_SECONDS_<CHAIN>` floor**: not needed (block time ≥ 1s).
- **`GAS_COMPARISON_MULTIPLIER_BY_CHAIN[137]`**: default `1.0` (basefee is real, dynamic, can spike — gas comparison matters).
- **`adjustmentPerGweiBaseFee`** in `DutchV3OrderFactory`: keep the default non-zero value; basefee is real wei.
- **`PRIORITY_ORDER_TARGET_BLOCK_BUFFER[137]` / `HYBRID_ORDER_TARGET_BLOCK_BUFFER[137]`**: set to `0` with comment unless those reactors are also deployed (no plans here).
- **`protocolFeeOwner`**: same as Arbitrum One — `0x2bad8182c09f50c8318d769245bea52c32be46cd` unless governance overrides.

## Notes

- **Reorg risk**: Bor consensus has a history of short reorgs (single-digit blocks; the well-known March 2022 incident reorged ~157 blocks but that's the outlier). For DutchV3 settlement, the `deadlineBufferSecs` and order-status polling should account for this — recommend `deadlineBufferSecs ≥ 30s` (≈ 15 blocks) so a swapper-signed deadline doesn't expire mid-reorg, and require ≥ 5-block confirmation in `check-order-status` before marking `FILLED`. This is more conservative than Ethereum mainnet (where deeper finality is provided by attestations) and stricter than fast L2s.
- **POL/MATIC rebrand**: token rebranded September 2024 from MATIC → POL at the same address. Universe already shows `symbol: 'POL'`. WPOL = WMATIC contract. No code change needed beyond display strings.
- **Public RPC reliability**: `polygon-rpc.com` failed for us (`API key disabled`) during this audit; production env should pin to Quicknode/Infura/drpc, not the public endpoint, for both `RPC_137` (parameterization-api / x-service / trading-api) and integ tests.
- **EIP-1559 minimum basefee**: Polygon enforced a 25 gwei floor in 2022 (later 30 gwei). Even at low congestion, basefee ≥ ~30 gwei — so the V3 gas-adjustment lever has signal here, unlike Tempo. Don't zero it.
