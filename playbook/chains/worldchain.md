# Worldchain (chainId 480) — DutchV3 rollout research

OP-stack L2 by Worldcoin (Tools for Humanity / Optimism Superchain). Native gas is ETH; WLD is the project/governance token, not gas. Standard Optimism Bedrock semantics — i.e. effectively a Base/Optimism/Unichain clone for our purposes.

## §0 — Pre-integration questionnaire

| Question | Answer |
|---|---|
| **chainId** | `480` (`eth_chainId` → `0x1e0`) |
| **RPC + explorer** | `https://worldchain-mainnet.g.alchemy.com/public` (Alchemy public; universe also wires QuickNode for `Public`/`Interface`) / `https://worldscan.org/` |
| **Block time (target)** | ~2s (universe `blockTimeMs: 2000`; observed 3 consecutive blocks at +2s deltas — see probe below) |
| **Finality model** | OP-stack Bedrock — soft confirmation at sequencer, hard finality on L1 (Ethereum) after batch posting + challenge window. Same model as Optimism/Base/Unichain. |
| **`block.number` semantics** | Standard EVM monotonic counter (OP-stack). No `BlockNumberish.sol` branch needed. |
| **`block.basefee` semantics** | Standard EIP-1559 wei. Observed `baseFeePerGas = 0x3d090` (250 000 wei = 0.00025 gwei) — low but real and dynamic. **No** `adjustmentPerGweiBaseFee = 0` override needed; gas-adjustment math works as on Optimism/Base. |
| **`block.timestamp` semantics** | Standard Unix seconds (observed contiguous 1778098289 → …91 → …93). |
| **Native gas token** | **ETH** (paid in ETH, 18 decimals, `DEFAULT_NATIVE_ADDRESS_LEGACY` sentinel). WLD is a regular ERC-20, not gas. WETH9 at `0x4200000000000000000000000000000000000006` (canonical OP-stack predeploy). NATIVE sentinel `address(0)` is supported. |
| **`CALLVALUE` / `BALANCE` / `SELFBALANCE` opcodes** | Standard — full ETH semantics. `payable` modifiers and the `BaseReactor` refund branch are live. Sample-executor native sweeps work. |
| **State creation costs** | Standard EVM gas schedule (OP-stack Bedrock matches mainnet costs). |
| **Permit2 at canonical address?** | ✅ Yes — `eth_getCode 0x000000000022D473030F116dDEE9F6B43aC78BA3` returns 18 306-byte bytecode. |
| **Sequencer / private mempool / pre-confs** | Single sequencer (Optimism Superchain operator model). Public mempool via the sequencer. No first-party pre-confs. Same exclusivity story as Optimism/Base — `ExclusivityLib` cosigner-window protection is the lever. |
| **EIP-1559 / typed tx support** | ✅ Yes (OP-stack Bedrock). `baseFeePerGas` populated; `eth_feeHistory` works. |
| **Routing surfaces (UniversalRouter, etc.)** | Universe declares `supportedURVersions: [_2_0, _2_1_1]` and `supportsV4: true`. Existing UniversalRouter / SwapRouter02 sample executors are reusable; no native-sweep caveats since ETH semantics are standard. |

### RPC probe (quick sanity)

```
$ curl -s -X POST https://worldchain-mainnet.g.alchemy.com/public \
    -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'
{"jsonrpc":"2.0","id":1,"result":"0x1e0"}              # 480

# Permit2 present
eth_getCode(0x000000000022D473030F116dDEE9F6B43aC78BA3) → 18306-byte runtime

# Arachnid CREATE2 deployer present
eth_getCode(0x4e59b44847b379578588920cA78FbF26c0B4956C) → 140-byte runtime

# 3 consecutive blocks @ head 29381327
num=29381325 ts=1778098289 baseFee=250000
num=29381326 ts=1778098291 baseFee=250000
num=29381327 ts=1778098293 baseFee=250000
# → +2s deltas, monotonic block number, real-but-low EIP-1559 basefee
```

## §1 — EVM compatibility audit

| Behavior | Worldchain | UniswapX impact |
|---|---|---|
| `block.number` monotonic & contiguous | ✅ standard | None |
| `block.basefee` real wei value | ✅ standard EIP-1559 (low: ~250k wei) | None — gas-adjustment math runs as on Optimism/Base |
| `block.timestamp` seconds since epoch | ✅ standard | None |
| `msg.value` reflects sent ETH | ✅ standard | None |
| `address(this).balance` reflects ETH balance | ✅ standard | None |
| Permit2 at canonical address | ✅ deployed | Reactor binds normally |
| EIP-1559 fields populated | ✅ | Cosigner reads `baseFeePerGas` from latest block as usual |
| Arachnid CREATE2 factory deployed | ✅ at `0x4e59…956C` | DutchV3 reactor + OrderQuoter deployable via the standard `script/DeployDutchV3.s.sol` flow |

**No chain-specific overrides required.** Worldchain behaves like Optimism/Base/Unichain for every UniswapX-relevant invariant.

## Existing UniswapX coverage

`@uniswap/uniswapx-sdk` (`/Users/cody.born/repos/sdks/sdks/uniswapx-sdk/src/constants.ts`) has **no** Worldchain entries:

- `PERMIT2_MAPPING[480]` → missing (add canonical `0x000000000022d473030f116ddee9f6b43ac78ba3`)
- `UNISWAPX_ORDER_QUOTER_MAPPING[480]` → missing (populate after lens deploy)
- `REACTOR_ADDRESS_MAPPING[480]` → missing (populate `[OrderType.Dutch_V3]` after reactor deploy; do NOT add Priority/Dutch_V2/Hybrid entries — only what's actually deployed)
- `EXCLUSIVE_FILLER_VALIDATION_MAPPING[480]` → falls through to default `0x8A66A74e15544db9688B68B06E116f5d19e5dF90`; verify that contract exists on Worldchain or add an explicit zero/redeploy.

`sdk-core` already has `ChainId.WORLDCHAIN = 480` (universe references `UniverseChainId.WorldChain`); confirm the exact enum spelling in `sdks/sdk-core/src/chains.ts` before wiring.

Trading-API / x-service / parameterization-api: no entries today — needs the standard §3.4–§3.6 additive changes from `NEW_CHAIN.md`.

## Deploy parameters (proposed)

| Param | Value | Rationale |
|---|---|---|
| `FOUNDRY_REACTOR_OWNER` | `0x2bad8182c09f50c8318d769245bea52c32be46cd` | Same `protocolFeeOwner` as Arbitrum/Tempo unless governance overrides. |
| `V3_DEFAULT_DECAY_DURATION_SECS` | `30` (default) | Standard wallclock decay. |
| `V3_BLOCK_LENGTH` | **15** = `ceil(30 / 2)` | 30s wallclock at 2s blocks. |
| `V3_BLOCK_BUFFER` | `4` (default) | 2s blocks are not sub-second; no need to tighten. |
| `BLOCK_TIME_MS_BY_CHAIN[480]` | `2000` | Matches universe `blockTimeMs`. |
| `AVERAGE_BLOCK_TIME(480)` (x-service) | `2` seconds | Whole-second; no `MIN_RETRY_WAIT_SECONDS_WORLDCHAIN` floor required. |
| `GAS_COMPARISON_MULTIPLIER_BY_CHAIN[480]` | `1.0` (default) | Real EIP-1559 basefee — keep gas-adjustment in the RFQ-vs-Classic comparison. |
| `adjustmentPerGweiBaseFee` (DutchV3OrderFactory) | non-zero default | Keep gas adjustment live — basefee is small but dynamic. |
| `WRAPPED_NATIVE_CURRENCY[480]` | WETH `0x4200…0006` | Standard OP-stack predeploy. NATIVE-sentinel orders are valid. |
| `PRIORITY_/HYBRID_ORDER_TARGET_BLOCK_BUFFER[480]` | `0` with comment | Only DutchV3 launching; reactor-mapping absence is the upstream guard. |

## Notes / chain-specifics

- **OP Superchain**: same operational profile as Optimism, Base, Unichain — sequencer-mediated, public mempool, OP-stack Bedrock. Filler integration risk is essentially zero on the EVM-behavior axis; the work is purely additive map entries plus contract deploys.
- **Very low basefee** (~0.00025 gwei observed): gas-adjustment math is correct but the absolute correction is tiny. Same as Base under low load — no special handling needed.
- **WLD ≠ gas**: WLD is just an ERC-20. Don't conflate with native; don't add it to `WRAPPED_NATIVE_CURRENCY`.
- **Bridge/UX**: official bridge `https://world-chain.superbridge.app/app`; canonical Across address `0x09aea4b2242abC8bb4BB78D537A67a245A7bEC64` (per universe). Not in scope for UniswapX rollout but useful for cross-chain context.
- **Readiness**: 🟢 — Permit2 + Arachnid both present, fully standard EVM/EIP-1559, native ETH, 2s blocks. Mechanical rollout — clone the Optimism/Base/Unichain pattern, no new corrections beyond `NEW_CHAIN.md`.
