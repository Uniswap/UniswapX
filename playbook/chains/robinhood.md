# Robinhood Chain (chainId 4663)

Status: 🟢 **Contracts deployed 2026-06-12** — `V3DutchOrderReactor` at `0x000000007A1C8e570011EeDF86A2A35593013cBA` (owner + permit2 verified on-chain; built from post-`BlockNumberish`-4663 bytecode so decay reads `ArbSys.arbBlockNumber()`), `OrderQuoter` at canonical `0x00000000a3db63Df9078cBF3dF88B4CAdD5a7F58`. Explorer verification + SDK/service wiring (Phases 2–4) pending.

Original audit assessment: 🟡 Has caveats. Arbitrum Orbit L2 on Ethereum (Nitro `v3.9.9`), ETH gas, Permit2 + Arachnid CREATE2 deployer present and functional. Two structural items, both now resolved:

1. **`BlockNumberish.sol` decision** — Orbit chains have Arbitrum One's split block-number semantics (`block.number` = parent-chain estimate, `ArbSys.arbBlockNumber()` = L2 count), but `src/base/BlockNumberish.sol` only special-cased chainid 42161. **Resolved**: 4663 added to the ArbSys branch (Option A below) + fresh salt mined against the new bytecode; deployed. The 17 previously-deployed chains run the pre-change bytecode (unaffected); future chains mine against the new bytecode and the canonical Tempo salt is retired.
2. **On-demand block production** — the chain is currently near-idle (~53K blocks total). Blocks arrive in sub-second bursts separated by multi-minute gaps. Block-driven V3 decay stalls when no blocks are produced. **Still the key launch-timing consideration** — see [Launch caveats](#launch-caveats).

v4 **is** deployed (PoolManager `0x8366a39cc670b4001a1121b8f6a443a643e40951`, per sdk-core `ROBINHOOD_ADDRESSES`); `PoolManager.owner()` returns the canonical `0x2bad8182c09f50c8318d769245bea52c32be46cd` (verified live 2026-06-12) — standard owner-derivation flow applies. Note the owner address has no code on Robinhood (the deploy script warns EOA-on-chain but doesn't block; same as other canonical-owner chains).

Source: live RPC probes against the QuikNode endpoint (2026-06-12) + [docs.robinhood.com/chain](https://docs.robinhood.com/chain/).

---

## §0 Pre-integration questionnaire

| Question | Answer |
|---|---|
| **chainId** | `4663` (`0x1237`) — mainnet. (Testnet is `46630`.) |
| **RPC + explorer URLs** | Probed via QuikNode: `https://dry-burned-surf.robinhood-mainnet.quiknode.pro/<key>/`. Public mainnet RPC + explorer URLs not yet published in docs (testnet: `rpc.testnet.chain.robinhood.com` / Blockscout at `explorer.testnet.chain.robinhood.com`) — **confirm mainnet equivalents with Robinhood before launch**. |
| **Block time (target)** | **On-demand** (standard Nitro): blocks only when txs arrive, ≥4 blocks/s possible under load (observed sub-second bursts), but multi-minute idle gaps today (observed 298s gap at block 52943→52944; ~37s/block average over the last 2K blocks). Treat as 250ms *under load*, unbounded when idle. |
| **Finality model** | Standard Orbit: sequencer soft-confirms instantly; Ethereum DA via blobs; L1 finality in ~13 min. Same trust model as Arbitrum One for filler purposes — treat sequencer receipt as final. |
| **`block.number` semantics** | **Non-standard (Arbitrum-style)**: returns the sequencer's estimate of the *Ethereum L1* block number (observed `l1BlockNumber` ≈ 25,303,216 vs L2 height 52,851). `ArbSys(0x64).arbBlockNumber()` returns the L2 height (verified live: `0xce73`). `eth_blockNumber` returns the **L2** height — matches ArbSys, not `block.number`. Needs the `BlockNumberish.sol` branch (see below). |
| **`block.basefee` semantics** | Real wei value, Orbit congestion pricing with a 0.1 gwei floor. Observed pinned at floor (`100000000`, one sample at `100020000`). Standard treatment — leave `adjustmentPerGweiBaseFee` default (it will be ~no-op at the floor, which is fine). |
| **`block.timestamp` semantics** | Standard Unix seconds (sequencer-assigned, monotonic). Deadline math safe — advances in wall-clock even when block production is idle. |
| **Native gas token** | ETH (docs: "Ethereum blobs for data availability and ETH as the native gas token"). `NATIVE` sentinel usable. Mainnet WETH at `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73` (sdk-core `WETH9[4663]`; `symbol() == WETH` verified live). |
| **`CALLVALUE` / `BALANCE` / `SELFBALANCE` opcodes** | Standard (Nitro). `payable` paths and sample-executor native sweeps work. |
| **State creation costs** | Standard Nitro gas schedule. No special pricing concern. |
| **Permit2 at canonical address?** | ✅ Yes — 9,152 bytes at `0x000000000022D473030F116dDEE9F6B43aC78BA3`, `DOMAIN_SEPARATOR()` returns non-zero (`0x4486...4fad`). |
| **Sequencer / private mempool / pre-confs** | Centralized Robinhood-operated sequencer (standard Orbit). Sequencer feed exists (testnet: `wss://feed.testnet.chain.robinhood.com`). No public mempool — RFQ exclusivity via `ExclusivityLib` as usual; sequencer ordering risk same class as Arbitrum One pre-BoLD. |
| **EIP-1559 / typed tx support** | ✅ Nitro supports type-2 txs; `baseFeePerGas` populated. |
| **Routing surfaces (UniversalRouter, etc.)** | Uniswap v3 + v4 deployed per sdk-core `ROBINHOOD_ADDRESSES`: v4 PoolManager `0x8366a39cc670b4001a1121b8f6a443a643e40951` (24KB code verified live), v3 factory `0x1f7d...2efa`, SwapRouter02 `0xcaf6...5cb2`, v4 Quoter `0x8dc1...8f94`. Multicall3 ✅ at canonical `0xcA11...CA11`. Classic-route quote source exists. |
| **protocolFeeOwner** | `0x2bad8182c09f50c8318d769245bea52c32be46cd` — derived from `PoolManager.owner()` (verified live 2026-06-12); happens to equal the canonical Arbitrum One owner. No code at that address on Robinhood (expected-multisig warning will fire; non-blocking). |

---

## §1 EVM compatibility audit

| Behavior | Standard? | Notes for Robinhood |
|---|---|---|
| `block.number` monotonic & contiguous | ⚠️ **No** | Arbitrum-style L1-block estimate: coarse (~12s granularity), advances in jumps. `eth_blockNumber` (what off-chain services poll) returns the L2 height instead. **Requires the ArbSys branch in `src/base/BlockNumberish.sol`** (currently gated to chainid 42161 only). |
| `block.basefee` real wei value | ✅ | Orbit pricing, 0.1 gwei floor, near-constant today. Standard treatment. |
| `block.timestamp` seconds since epoch, monotonic | ✅ | Standard. |
| `msg.value` reflects sent ETH | ✅ | Standard. |
| `address(this).balance` reflects ETH balance | ✅ | Standard; sample-executor native sweeps fine. |
| Permit2 deployed at canonical address | ✅ | Verified + functional. |
| Arachnid CREATE2 deployer present | ✅ | 69 bytes at `0x4e59b44847b379578588920cA78FbF26c0B4956C`. |
| EIP-1559 fields populated | ✅ | Standard Nitro. |
| Canonical reactor address free | ✅ | No code at `0x000000005aF66799D1a6317714D66800f9CA1406` (moot — see salt note below). |

---

## BlockNumberish decision

`V3DutchOrderReactor` resolves decay via `_getBlockNumberish()` (`src/reactors/V3DutchOrderReactor.sol:65`). On Robinhood the two candidate sources disagree:

| | **Option A — add 4663 to the ArbSys branch (recommended)** | Option B — deploy unmodified (use `block.number`) |
|---|---|---|
| On-chain decay source | L2 block height (250ms granularity under load) | L1-block estimate (~12s granularity, mainnet-like) |
| Off-chain consistency | ✅ `eth_blockNumber` == `arbBlockNumber` on Nitro — parameterization-api `decayStartBlock`, x-service polling, and the SDK all work unchanged (exactly like Arbitrum One) | ❌ `eth_blockNumber` (L2 height ≈ 53K) ≠ `block.number` (≈ 25.3M). Every off-chain consumer must switch to reading `l1BlockNumber` for this chain or cosigned orders resolve as fully-decayed/never-started. High-risk, invasive service changes. |
| Idle-chain behavior | ⚠️ Decay stalls while no blocks are produced (L2 height freezes) | Decay tracks wall-clock via L1 estimate |
| Bytecode impact | ⚠️ creationCode changes → fresh salt for Robinhood; canonical Tempo salt becomes invalid for any *future* chain deployed from the new bytecode (the 17 already-deployed chains are unaffected) | None |

Option B's wall-clock decay is attractive in isolation, but it silently breaks the `eth_blockNumber`-based assumptions baked into parameterization-api, x-service, and the SDK — the bug class is "order instantly fully decayed," which is swapper-money-losing. Option A keeps Robinhood byte-for-byte consistent with the Arbitrum One mental model everywhere off-chain, and the idle-stall risk is bounded: deadlines are timestamp-based (they expire normally), RFQ-cosigned fills don't depend on decay progression, and any fill/trade activity itself produces blocks. Mitigate the stall with launch-timing + monitoring (below) rather than novel semantics.

**The change** (in `src/base/BlockNumberish.sol`, constructor):

```solidity
uint256 private constant ARB_CHAIN_ID = 42161;
uint256 private constant ROBINHOOD_CHAIN_ID = 4663;
...
if (block.chainid == ARB_CHAIN_ID || block.chainid == ROBINHOOD_CHAIN_ID) {
    _getBlockNumberish = _getBlockNumberSyscall;
}
```

(ArbSys is a Nitro precompile at `0x64` on every Orbit chain — `arbBlockNumber()` verified live on Robinhood mainnet.)

Note the same 42161-only gating exists in `lib/blocknumberish` (used by `src/v4/resolvers/HybridAuctionResolver.sol`) — out of scope for the DutchV3 rollout but file an issue so v4 resolvers don't regress on Orbit chains later.

**Ordering vs Arc:** Arc's PoolManager owner is *not* canonical, so Arc needs its own mining run regardless. Land this change first, then mine both chains' salts against the same bytecode/toolchain state (`./scripts/mine-salt.sh 4663 && ./scripts/mine-salt.sh 5042`). The in-script `predicted == V3_REACTOR_EXPECTED` assert makes any bytecode/salt mismatch fail safe (abort, no gas spent).

---

## Deploy parameters

| Parameter | Value | Rationale |
|---|---|---|
| `FOUNDRY_REACTOR_OWNER` | `0x2bad8182c09f50c8318d769245bea52c32be46cd` | Derived from `PoolManager.owner()` at `0x8366a39cc670b4001a1121b8f6a443a643e40951`. |
| `V3_REACTOR_SALT` / `V3_REACTOR_EXPECTED` | `0x...1585866b75f2b774c6520080` / `0x000000007A1C8e570011EeDF86A2A35593013cBA` — **mined + deployed 2026-06-12** (4 leading + 5 total zero bytes) | Mined against post-4663-branch bytecode (macOS + forge 1.4.4 + solc 0.8.30); deployer `0xA53247dEeC5884B5A10667dee1C378e729a93e03`, ~0.0011 ETH gas. |
| Deploy route | `scripts/deploy-v3-multichain.sh` works (poolManager + owner now in salts.json; owner-drift precondition passes) — pass `RPC_4663=<url>` since `default_rpc()` has no 4663 entry. Direct single-chain invocation also fine. | — |
| Lens | OrderQuoter — **canonical address `0x00000000a3db63Df9078cBF3dF88B4CAdD5a7F58` still works** | OrderQuoter doesn't inherit BlockNumberish; its initcode is unchanged → same salt/address as all other chains. Use `script/DeployOrderQuoter.s.sol`. |
| Deployer gas funding | ETH on Robinhood (bridge via the chain's canonical bridge) | ~0.05 ETH headroom per `MIN_BALANCE_WEI` convention. |
| `BLOCK_TIME_MS_BY_CHAIN[4663]` (x-service) | `250` | Nitro under-load cadence; mirror Arbitrum One's entry. |
| `AVERAGE_BLOCK_TIME(4663)` (x-service) | mirror Arbitrum One | Same Nitro semantics. |
| `MIN_RETRY_WAIT_SECONDS_<CHAIN>` floor | **needed** (sub-second blocks under load) — mirror whatever Arbitrum One does today; if Arbitrum has no floor, add `2` for 4663 | Correction D: Step Functions Wait rounds sub-second to 0 → hot loop. |
| `V3_BLOCK_LENGTH_BY_CHAIN[4663]` (trading-api) | `120` (= 30s at 250ms), Arbitrum parity | Wallclock-correct only under load; see launch caveats. |
| `V3_BLOCK_BUFFER` (parameterization-api) | mirror Arbitrum One's value | Same block cadence + `eth_blockNumber` semantics under Option A. |
| `getBlockTimeSecs(4663)` (parameterization-api) | `0.25` | — |
| `GAS_COMPARISON_MULTIPLIER_BY_CHAIN[4663]` | `1.0` (default) | Real wei basefee; gas is cheap but not denominated weirdly. |
| `WRAPPED_NATIVE_CURRENCY[4663]` | WETH `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73` | sdk-core `WETH9[4663]`, symbol verified live. Native ETH is real; do *not* reject the native sentinel. |
| `adjustmentPerGweiBaseFee` (DutchV3OrderFactory) | default (non-zero path) | Standard wei basefee. Near-no-op at the 0.1 gwei floor — harmless. |
| `PRIORITY_ORDER_TARGET_BLOCK_BUFFER[4663]`, `HYBRID_…[4663]` | `0` with comment | No Priority/Hybrid reactor at launch; `validateReactorAddress` rejects upstream. |
| `OLDEST_BLOCK_BY_CHAIN[4663]` (x-service) | ~`52900` (block at 2026-06-12) | Chain is brand new. |

---

## Launch caveats

- **Decay stalls on an idle chain.** Under Option A, V3 decay advances one step per L2 block. Today the chain idles for minutes at a time → a "30s" (120-block) decay can take arbitrarily long, so open-market price improvement degrades to "sit at cosigned start price until deadline." RFQ-cosigned fills are unaffected (filler fills at the cosigned override immediately), and order deadlines expire on wall-clock as normal. **Recommendation:** launch UniswapX only once baseline Robinhood activity sustains regular block production, or accept RFQ-dominant behavior at first; add a dashboard panel for L2 blocks/minute and alert if decay-window wallclock (decayStartBlock → currentBlock × 250ms vs. real elapsed time) diverges >5×.
- **Public mainnet RPC + explorer unpublished.** Robinhood's public docs are testnet-only as of 2026-06-12 (Blockscout expected for mainnet, mirroring testnet). Collect from the Robinhood team; verify explorer supports contract verification before the deploy (Blockscout: `forge verify-contract --verifier blockscout --verifier-url <explorer>/api`).
- **sdk-core is a no-op**: `ChainId.ROBINHOOD = 4663` is already in `@uniswap/sdk-core` with the full v3/v4 `ROBINHOOD_ADDRESSES` block and `WETH9[4663]`. Phase 1 reduces to the x-contracts deploy.
- **Classic routing exists** (v3 + v4 + SwapRouter02 live on-chain), so `compareQuotes` has a real Classic leg. Confirm the routing stack (URA/trading-api Classic path) is actually serving Robinhood quotes before flipping the flag.
