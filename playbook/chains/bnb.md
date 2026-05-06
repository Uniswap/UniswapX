# BNB Smart Chain — DutchV3 rollout research

Status: 🟡 Has caveats (zero basefee + sub-second blocks post-Maxwell)

Per `playbook/NEW_CHAIN.md` §0 + §1. Probed 2026-05-01 against
`https://bsc-dataseed.binance.org`.

## §0 Pre-integration questionnaire

| Question | BNB answer |
|---|---|
| **chainId** | `56` (`eth_chainId` → `0x38`) |
| **RPC + explorer URLs** | `https://bsc-dataseed.binance.org` (or `https://bsc-dataseed1.bnbchain.org` per universe `bnb.ts`) / `https://bscscan.com` |
| **Block time (target)** | **~0.47s observed** (30-block sample: 14s wallclock / 30 blocks). Universe `bnb.ts` still records `blockTimeMs: 3000` — out of date. Post-Maxwell hardfork (mid-2025) block time dropped from 3s → 0.75s, and live chain is currently producing sub-second. Treat as sub-second for all downstream math. |
| **Finality model** | PoSA (Parnassus PoS-Authority) with 21+ active validators; ~2 epochs (~750 blocks) for economic finality. Reorg risk higher than Ethereum L1 — use `BLOCK_TIME_MS_BY_CHAIN[56] = 750` (matches Maxwell target) and add the standard reorg buffer in `check-order-status`. |
| **`block.number` semantics** | Standard EVM monotonic counter. Verified contiguous. **No** `BlockNumberish.sol` branch needed. |
| **`block.basefee` semantics** | **Always `0x0`** on every recent block (verified at head and 1000-blocks-ago). BNB does not run an EIP-1559 fee market; the 1-gwei minimum gas price is enforced off-chain by validators. **Set `adjustmentPerGweiBaseFee = 0` in `DutchV3OrderFactory` for chainId 56** — same lever as Tempo. |
| **`block.timestamp` semantics** | Standard Unix seconds (verified monotonic across sampled range). |
| **Native gas token** | BNB (18 decimals). `address(0)` NATIVE sentinel is meaningful here. WBNB at `0xbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c`. |
| **`CALLVALUE` / `BALANCE` / `SELFBALANCE` opcodes** | Standard EVM — BNB carries native value. `payable` modifiers and reactor refund branch are live. Sample-executor native sweeps work. |
| **State creation costs** | Standard EVM gas schedule. Not economically interesting at 1 gwei + sub-cent BNB. |
| **Permit2 at canonical address?** | ✅ Yes — `0x000000000022D473030F116dDEE9F6B43aC78BA3` has 18306 chars of code (verified `eth_getCode`). |
| **Sequencer / private mempool / pre-confs** | Public mempool with PoSA validator rotation. No native pre-confs. MEV via 48-Club / bloXroute is significant — exclusivity protection from `ExclusivityLib` remains the primary RFQ defence. |
| **EIP-1559 / typed tx support** | Type-2 txs accepted; `baseFeePerGas` field is populated but always `0x0`. Cosigner reading `baseFeePerGas` from latest block will get 0 — fine, but means it's unusable as a tripwire. |
| **Routing surfaces (UniversalRouter, etc.)** | UR v2.0 + v2.1.1 supported per universe `bnb.ts`. Existing sample executors (`UniversalRouterExecutor`, `SwapRouter02Executor`) reusable as-is. |

### Probe one-liner used

```bash
RPC=https://bsc-dataseed.binance.org
N=$(curl -s -X POST $RPC -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  | python3 -c "import sys,json;print(int(json.load(sys.stdin)['result'],16))")
for i in 0 1 2; do
  HEX=$(printf "0x%x" $((N-2+i)))
  curl -s -X POST $RPC -H 'Content-Type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getBlockByNumber\",\"params\":[\"$HEX\",false],\"id\":1}" \
    | python3 -c "import sys,json;b=json.load(sys.stdin)['result'];print(int(b['number'],16),int(b['timestamp'],16),b.get('baseFeePerGas'))"
done
```

## §1 EVM compatibility audit

| Behavior | BNB | Action |
|---|---|---|
| `block.number` monotonic & contiguous | ✅ | None |
| `block.basefee` real wei value | ❌ **always 0** | **Set `adjustmentPerGweiBaseFee = 0` in `DutchV3OrderFactory` for chainId 56** |
| `block.timestamp` seconds since epoch, monotonic | ✅ | None |
| `msg.value` reflects sent value | ✅ | None |
| `address(this).balance` reflects native balance | ✅ | None |
| Permit2 deployed at canonical address | ✅ verified | None |
| Arachnid CREATE2 deployer present | ✅ verified at `0x4e59b44847b379578588920cA78FbF26c0B4956C` (140 bytes of code) | None — proxy-deployed reactor address will match other chains |
| EIP-1559 fields populated | ✅ (basefee field present, value 0) | Cosigner cannot use basefee tripwire on BNB |

## Existing UniswapX coverage (chainId 56)

Verified against `sdks/sdks/uniswapx-sdk/src/constants.ts`:

- `PERMIT2_MAPPING[56]` — **absent** (would resolve to undefined; needs entry).
- `UNISWAPX_ORDER_QUOTER_MAPPING[56]` — **absent**.
- `REACTOR_ADDRESS_MAPPING[56]` — **absent** (no Dutch / Dutch_V2 / Dutch_V3 / Priority / Hybrid / Relay entry).
- `EXCLUSIVE_FILLER_VALIDATION_MAPPING[56]` — **absent**.

BNB is **not** in `NETWORKS_WITH_SAME_ADDRESS`, so it picks up no fall-through. Greenfield SDK wiring required.

## Deploy parameters

- **Reactor**: `V3DutchOrderReactor` via `script/DeployDutchV3.s.sol`, CREATE2-deployed through Arachnid factory → address will match Arbitrum / Tempo deployments.
- **Quoter**: `OrderQuoter` lens — same script.
- `FOUNDRY_REACTOR_OWNER=0x2bad8182c09f50c8318d769245bea52c32be46cd` (matches Arbitrum One protocolFeeOwner).
- **Decay block length**: questionnaire prompt suggested `ceil(30/3) = 10`, but **observed block time is ~0.47s**, not 3s. Recompute: `V3_BLOCK_LENGTH_BY_CHAIN[56] = ceil(30 / 0.75) = 40` if pinning to the Maxwell 0.75s target, or `ceil(30 / 0.47) ≈ 64` against current empirical. Recommend **40** (Maxwell target) with a follow-up to re-tune after observing post-launch block-time variance.
- **`V3_BLOCK_BUFFER`**: `1` (sub-second blocks; matches Tempo precedent).
- **`MIN_RETRY_WAIT_SECONDS_BNB = 2`** in x-service `calculateDutchRetryWaitSeconds` (Correction D — sub-second blocks need a chain-scoped retry floor).
- **`GAS_COMPARISON_MULTIPLIER_BY_CHAIN[56] = 0`** in trading-api (basefee is constant 0; gas adjustment is structurally a no-op).

## Notes

- BNB universe `bnb.ts` has stale `blockTimeMs: 3000`. Treat the empirical 0.47s as ground truth; when adding to `BLOCK_TIME_MS_BY_CHAIN`, use `750` (Maxwell target) as the engineering value and file a separate issue to update universe.
- Native BNB token means the Tempo-style "no native, hard-reject 0x0 sentinel at API boundary" carve-out does **not** apply. Standard NATIVE handling (mirror Mainnet/Polygon).
- Basefee = 0 puts BNB in the same factory-tweak bucket as Tempo (`adjustmentPerGweiBaseFee = 0`), but for a different reason: Tempo denominates basefee non-standardly; BNB has no basefee market at all. The lever is identical.
- Cosigner `startingBaseFee` tripwire cannot be exercised on BNB — note this in the cosigner code path.
- Higher reorg risk than Ethereum/Arbitrum/Base — extend `OLDEST_BLOCK_BY_CHAIN[56]` window and consider raising fill-confirmation depth in `check-order-status` from default to 3+ blocks.
- 48-Club / bloXroute private orderflow is dominant on BNB; RFQ-only quoting flow with whitelisted PMM addresses is the right canary posture (Phase 4 of §5).
