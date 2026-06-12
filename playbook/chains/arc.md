# Arc (chainId 5042)

Status: 🟢 **Contracts deployed 2026-06-12** — `V3DutchOrderReactor` at `0x0000000015134054eA82AE0bb9fda66b36402C36` (owner + permit2 verified on-chain), `OrderQuoter` at canonical `0x00000000a3db63Df9078cBF3dF88B4CAdD5a7F58`. Explorer verification + SDK/service wiring (Phases 2–4) pending. Config caveats below still apply to the service rollout.

Original audit assessment: 🟡 Has caveats, but mechanically ready — no contract-code changes needed. Circle's stablecoin-native L1 (reth `v1.11.3` execution, Malachite BFT consensus). Permit2 + Arachnid CREATE2 deployer present and functional. Caveats are all config-side, and all have Tempo/Celo precedent:

1. **USDC is the native gas token** with dual representation: 18-decimal native (`eth_getBalance`/`msg.value`) and a 6-decimal ERC-20 interface predeploy at `0x3600000000000000000000000000000000000000` over the *same balance* (verified live: same account shows `9355344270750000000` native and `9355344` via `balanceOf`). Celo-style, not Tempo-style — `CALLVALUE`/`BALANCE` work normally.
2. **Constant basefee** (20 gwei, unchanged across 1M+ blocks ≈ 5.8 days) → `adjustmentPerGweiBaseFee = 0`, `GAS_COMPARISON_MULTIPLIER = 0`.
3. **Sub-second blocks** (~500ms) → Tempo-style `MIN_RETRY_WAIT` floor + `V3_BLOCK_BUFFER = 1`.

v4 **is** deployed (PoolManager `0x8366a39cc670b4001a1121b8f6a443a643e40951`, per sdk-core `ARC_ADDRESSES`); `PoolManager.owner()` returns `0x33f26c5d69e2c40956f22c6195b6a499cf4151e8` (verified live 2026-06-12; a 171-byte proxy on Arc, likely a Safe). That is **not** the canonical owner, so the canonical Tempo salt does **not** apply — **Arc needs its own `(salt, expectedReactor)` pair mined** via `./scripts/mine-salt.sh 5042`, after the Robinhood `BlockNumberish.sol` change lands so both chains share one bytecode state.

Source: live RPC probes against the QuikNode endpoint (2026-06-12) + [docs.arc.io](https://docs.arc.io) (docs still testnet-focused; predeploys verified directly on mainnet).

---

## §0 Pre-integration questionnaire

| Question | Answer |
|---|---|
| **chainId** | `5042` (`0x13b2`) — mainnet. (Testnet is `5042002`.) |
| **RPC + explorer URLs** | Probed via QuikNode: `https://cool-compatible-friday.arc-mainnet.quiknode.pro/<key>/`. Explorer: Arcscan (testnet at `testnet.arcscan.app`; mainnet URL to confirm — `explorer.arc.io` responds with a redirect). |
| **Block time (target)** | ~500ms steady (observed 20 consecutive blocks over 10s, 2 blocks/s, including empty blocks — continuous production, not on-demand). |
| **Finality model** | Malachite BFT — deterministic sub-second finality (per Circle docs). Treat 1 confirmation as final; no reorgs in normal operation. |
| **`block.number` semantics** | Standard EVM monotonic counter (reth; height ~4.83M). No `BlockNumberish.sol` branch needed. |
| **`block.basefee` semantics** | **Constant `20000000000` (20 gwei)** — flat across samples spanning 1M blocks. Denominated in native-USDC wei (1e-18 USDC), so gas costs 2e-8 USDC/gas — numerically identical to Tempo's `2e10` attodollars. `eth_maxPriorityFeePerGas` suggests 5 gwei, so tips exist, but basefee itself doesn't move → zero the gas-adjustment levers (see deploy params). |
| **`block.timestamp` semantics** | Standard Unix seconds. |
| **Native gas token** | **USDC** — native asset at 18-decimal precision; canonical 6-decimal ERC-20 interface predeploy at `0x3600000000000000000000000000000000000000` (symbol `USDC`, `decimals() = 6`, standard `allowance`/`totalSupply` verified). Same balance, two precisions — **never mix the representations** (12-decimal scale factor). No wrapped-USDC contract exists (none needed). |
| **`CALLVALUE` / `BALANCE` / `SELFBALANCE` opcodes** | Standard — native USDC flows through `payable` paths (unlike Tempo). Reactor's `NATIVE` sentinel would *work* mechanically, but reject it at the API boundary anyway (see Notes). |
| **State creation costs** | Standard reth gas schedule; at the constant 20 gwei USDC-wei basefee, a 250K-gas cold fill costs ~$0.005. Immaterial (Correction F). |
| **Permit2 at canonical address?** | ✅ Yes — 9,152 bytes at `0x000000000022D473030F116dDEE9F6B43aC78BA3`, `DOMAIN_SEPARATOR()` non-zero (`0xa88a...b18f`). Listed as an official Arc predeploy in Circle's docs. |
| **Sequencer / private mempool / pre-confs** | Permissioned Malachite validator set operated by Circle + partners. No public-mempool MEV in the Ethereum sense; RFQ exclusivity via reactor `ExclusivityLib` as usual. |
| **EIP-1559 / typed tx support** | ✅ Type-2 txs; `baseFeePerGas` populated (constant), `eth_maxPriorityFeePerGas` live. Cosigner tripwire on `startingBaseFee` is trivially stable. |
| **Routing surfaces (UniversalRouter, etc.)** | Uniswap v3 + v4 deployed per sdk-core `ARC_ADDRESSES`: v4 PoolManager `0x8366a39cc670b4001a1121b8f6a443a643e40951` (24KB code verified live), v3 factory `0xf0db...3918`, SwapRouter02 `0x53bf...6f77`, v4 Quoter `0x8dc1...8f94`. Multicall3 ✅ at canonical `0xcA11...CA11`. Classic-route quote source exists. |
| **protocolFeeOwner** | `0x33f26c5d69e2c40956f22c6195b6a499cf4151e8` — derived from `PoolManager.owner()` (verified live 2026-06-12). Contract on Arc (171-byte proxy, likely Safe) — passes the expected-multisig sanity check. |

---

## §1 EVM compatibility audit

| Behavior | Standard? | Notes for Arc |
|---|---|---|
| `block.number` monotonic & contiguous | ✅ | Standard reth counter. |
| `block.basefee` real wei value | ⚠️ **Constant** | Real field, but pinned at 20 gwei (USDC-wei). Set `adjustmentPerGweiBaseFee = 0` in `DutchV3OrderFactory` for 5042 (Correction B: factory-side, swapper-signed payload). |
| `block.timestamp` seconds since epoch, monotonic | ✅ | Standard. |
| `msg.value` reflects sent native | ✅ | Native = USDC at 18 decimals. `payable` paths work (unlike Tempo). |
| `address(this).balance` reflects native balance | ✅ | Sample-executor native sweeps mechanically work, but sweep *USDC*, not ETH — semantics differ from what executor integrators expect; prefer ERC-20-only flows. |
| Permit2 deployed at canonical address | ✅ | Verified + functional. **Permit2 works against the 6-decimal ERC-20 interface** (standard `allowance`/`transferFrom` surface). |
| Arachnid CREATE2 deployer present | ✅ | 69 bytes at canonical address (official Arc predeploy). |
| EIP-1559 fields populated | ✅ | Populated; basefee constant. |
| Reactor address availability | ✅ | Fresh salt will be mined for owner `0x33f2...51e8`; CREATE2 derivation guarantees a virgin address. |

Non-standard cells → add an "Arc deployment notes" section to `README.md` post-deploy (constant basefee, USDC-native dual decimals, native-sentinel API rejection), mirroring the Tempo block.

---

## Existing UniswapX coverage (uniswapx-sdk `src/constants.ts`)

All four maps need new `5042` entries after deploy:

- `PERMIT2_MAPPING[5042]` → `0x000000000022d473030f116ddee9f6b43ac78ba3`
- `REACTOR_ADDRESS_MAPPING[5042]` → `{ [OrderType.Dutch_V3]: 0x0000000015134054eA82AE0bb9fda66b36402C36 }` (deployed 2026-06-12)
- `UNISWAPX_ORDER_QUOTER_MAPPING[5042]` → `0x00000000a3db63Df9078cBF3dF88B4CAdD5a7F58` (uniform canonical quoter — OrderQuoter initcode is owner-independent, so its canonical address still applies)
- `EXCLUSIVE_FILLER_VALIDATION_MAPPING[5042]` → zero address (reactor-enforced exclusivity)

`@uniswap/sdk-core` is a no-op: `ChainId.ARC = 5042` is already shipped with the full v3/v4 `ARC_ADDRESSES` block (and correctly no `WETH9` entry — Correction E territory). Phase 1 reduces to the x-contracts deploy.

---

## Deploy parameters

| Parameter | Value | Rationale |
|---|---|---|
| `FOUNDRY_REACTOR_OWNER` | `0x33f26c5d69e2c40956f22c6195b6a499cf4151e8` | Derived from `PoolManager.owner()` at `0x8366a39cc670b4001a1121b8f6a443a643e40951` (proxy/Safe on Arc). |
| `V3_REACTOR_SALT` / `V3_REACTOR_EXPECTED` | `0x...179cec38645d390d013a0040` / `0x0000000015134054eA82AE0bb9fda66b36402C36` — **mined + deployed 2026-06-12** | Owner is not canonical → Tempo salt did not apply; fresh pair mined (4 leading + 4 total zero bytes). |
| Deploy route (as executed) | Direct single-chain `forge script script/DeployDutchV3.s.sol` invocation from macOS, deployer `0xA53247dEeC5884B5A10667dee1C378e729a93e03`, ~0.22 native USDC gas | Deployed **before** the Robinhood `BlockNumberish.sol` 4663 branch (Arc-first ordering) — this reactor runs pre-change bytecode, which is equivalent on Arc (standard `block.number`). |
| Lens | OrderQuoter at canonical `0x00000000a3db63Df9078cBF3dF88B4CAdD5a7F58` via `script/DeployOrderQuoter.s.sol` | Chain-independent initcode. |
| Deployer gas funding | **Native USDC on Arc** (CCTP domain 26) | `MIN_BALANCE_WEI = 5e16` ≈ 0.05 native USDC — i.e. five cents. Whole deploy costs well under $1. |
| `BLOCK_TIME_MS_BY_CHAIN[5042]` (x-service) | `500` | Observed 2 blocks/s. |
| `AVERAGE_BLOCK_TIME(5042)` (x-service) | `1` (or fractional if supported — mirror Tempo's entry) | 500ms real. |
| `MIN_RETRY_WAIT_SECONDS_ARC` floor (x-service) | `2` | Correction D — sub-second blocks; chain-scoped, mirror Tempo. |
| `V3_BLOCK_LENGTH_BY_CHAIN[5042]` (trading-api) | `60` | `ceil(30 / 0.5)` — Tempo parity. |
| `V3_BLOCK_BUFFER` (parameterization-api) | `1` | Fast blocks — Tempo parity. |
| `getBlockTimeSecs(5042)` (parameterization-api) | `0.5` | — |
| `GAS_COMPARISON_MULTIPLIER_BY_CHAIN[5042]` | `0` | Gas is constant sub-cent USDC; RFQ-vs-Classic gas comparison is noise. |
| `adjustmentPerGweiBaseFee` (DutchV3OrderFactory) | `0` for 5042 | Constant basefee (Correction B — set in the factory, not the cosigner). |
| `WRAPPED_NATIVE_CURRENCY[5042]` | **do not populate** | No wrapped token exists; the ERC-20 interface *is* USDC. Hard-reject `0x0` sentinel at `src/api/quote/schema.ts` (Correction E / Tempo pattern) and require the `0x3600...0000` ERC-20 address. |
| `PRIORITY_ORDER_TARGET_BLOCK_BUFFER[5042]`, `HYBRID_…[5042]` | `0` with comment | No Priority/Hybrid reactor; `validateReactorAddress` rejects upstream. |
| `OLDEST_BLOCK_BY_CHAIN[5042]` (x-service) | ~`4829000` (block at 2026-06-12) | — |

---

## Notes

- **Native-sentinel policy.** Unlike Tempo, `0x0` orders would mechanically work (reactor can transfer native USDC). Reject them anyway: output amounts for `0x0` would be 18-decimal native-USDC wei while every USDC integration on Arc speaks the 6-decimal ERC-20 — a silent 1e12 decimals mismatch waiting to happen. One asset, one address: `0x3600000000000000000000000000000000000000`, 6 decimals.
- **Decimals trap is the #1 integration risk.** Quoting/accounting must treat Arc USDC as 6 decimals (ERC-20 interface). Anything reading `eth_getBalance` for USDC (filler balance checks, MIN_BALANCE-style preflights) gets 18-decimal units. `scripts/deploy-v3-multichain.sh`'s `MIN_BALANCE_WEI` happens to be safe (5e16 native ≈ $0.05).
- **Stablecoin canary pairs.** USDC (`0x3600...0000`) is the anchor; confirm which other stables (EURC, USYC, etc.) are live on Arc mainnet with a PMM before picking the canary pair — docs list testnet assets only.
- **Sample executors.** Mechanically functional, but their native-sweep paths sweep USDC; recommend MMs use ERC-20-only flows. Same guidance as Tempo, softer reason.
- **Verification.** Confirm Arcscan's verifier API (Etherscan-compatible vs Blockscout) before deploy; `explorer.arc.io` redirect suggests a hosted explorer exists.
- **Cosigner tripwire.** With a constant basefee, parameterization-api's (future) `startingBaseFee` divergence tripwire is trivially implementable for Arc — any observed value ≠ 2e10 is anomalous.
