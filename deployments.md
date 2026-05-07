# UniswapX V3 deployments

`V3DutchOrderReactor` + `OrderQuoter` deployed across all chains the Uniswap
AMM front-end currently supports (see `playbook/chains/README.md` for the
chain list). All deploys go through the canonical Arachnid CREATE2 factory
(`0x4e59b44847b379578588920cA78FbF26c0B4956C`).

- **Reactor**: per-chain `(salt, address)` pair mined against `(PERMIT2,
  owner)`, where owner is read from each chain's v4 `PoolManager.owner()`.
  Per-chain config in `playbook/chains/salts.json`. Deploy script:
  `script/DeployDutchV3.s.sol` + multi-chain wrapper
  `scripts/deploy-v3-multichain.sh`.
- **OrderQuoter**: stateless lens with no constructor args, so a single
  global salt produces the **same address on every chain**. Deploys to
  `0x00000000a3db63Df9078cBF3dF88B4CAdD5a7F58` everywhere. Deploy script:
  `script/DeployOrderQuoter.s.sol` + multi-chain wrapper
  `scripts/deploy-quoter-multichain.sh`.

Deployed by `0x2179a60856E37dfeAacA0ab043B931fE224b27B6` on **2026-05-07**
(except Optimism, which had been deployed by an earlier broadcast attempt
that ran into a mainnet gas-limit issue, and Tempo's pre-existing OrderQuoter
from ECO-365 phase 1b).

## OrderQuoter address

Same address on every chain: **`0x00000000a3db63Df9078cBF3dF88B4CAdD5a7F58`**.

| Chain | ID | Status | Verified |
|---|---|---|---|
| Mainnet | 1 | ✅ deployed | ✅ Etherscan |
| Optimism | 10 | ✅ deployed | ✅ Etherscan |
| BNB | 56 | ✅ deployed | ✅ Etherscan |
| Unichain | 130 | ✅ deployed (via `cast send` fallback — public RPC pruning blocked forge) | ✅ Etherscan |
| Polygon | 137 | ✅ deployed | ✅ Etherscan |
| Monad | 143 | ✅ deployed | ✅ Etherscan (V2 unified URL) |
| XLayer | 196 | ✅ deployed | ❌ (OKLink: manual upload only) |
| Worldchain | 480 | ✅ deployed | ✅ Etherscan |
| Soneium | 1868 | ✅ deployed | ✅ Sourcify (Blockscout) |
| Tempo | 4217 | ✅ pre-existing (ECO-365 phase 1b) | ✅ Sourcify |
| Base | 8453 | ✅ deployed (recovered after a transient Cloudflare 502) | ✅ Etherscan |
| Arbitrum | 42161 | ✅ deployed | ✅ Etherscan |
| Celo | 42220 | ✅ deployed | ✅ Etherscan |
| Avalanche | 43114 | ✅ deployed | ✅ Etherscan |
| Linea | 59144 | (deferred — same as reactor, no v4 PoolManager) | — |
| Blast | 81457 | ✅ deployed | ✅ Etherscan |
| Zora | 7777777 | ✅ deployed | ✅ Blockscout |

## Reactor addresses

| Chain | ID | Reactor address | Protocol fee owner | Verified |
|---|---|---|---|---|
| Mainnet | 1 | [`0x0000000015757c461808EA25Eb309638B62681cf`](https://etherscan.io/address/0x0000000015757c461808EA25Eb309638B62681cf) | `0x1a9C8182C09F50C8318d769245beA52c32BE35BC` | ✅ |
| Optimism | 10 | [`0x000000000923439A92daE8930613568824108631`](https://optimistic.etherscan.io/address/0x000000000923439A92daE8930613568824108631) | `0xa1dD330d602c32622AA270Ea73d078B803Cb3518` | ✅ |
| BNB | 56 | [`0x00000000a55e50C71b70Db3C8B58749cd1E18eB2`](https://bscscan.com/address/0x00000000a55e50C71b70Db3C8B58749cd1E18eB2) | `0x341c1511141022cf8eE20824Ae0fFA3491F1302b` | ✅ |
| Unichain | 130 | [`0x000000005aF66799D1a6317714D66800f9CA1406`](https://uniscan.xyz/address/0x000000005aF66799D1a6317714D66800f9CA1406) | `0x2bad8182c09f50c8318d769245bea52c32be46cd` | ✅ |
| Polygon | 137 | [`0x00000000bAB6E234db8AD638B6A6395b7c499Bc4`](https://polygonscan.com/address/0x00000000bAB6E234db8AD638B6A6395b7c499Bc4) | `0x8a1B966aC46F42275860f905dbC75EfBfDC12374` | ✅ |
| Monad | 143 | [`0x000000000Ac008F7e07210CFb6648e40249232c2`](https://monadscan.com/address/0x000000000Ac008F7e07210CFb6648e40249232c2) | `0xE783DE89a7F0408687f051e3E6D0BEb62719EbAd` | ✅ |
| XLayer | 196 | [`0x000000005aF66799D1a6317714D66800f9CA1406`](https://www.oklink.com/xlayer/address/0x000000005aF66799D1a6317714D66800f9CA1406) | `0x2bad8182c09f50c8318d769245bea52c32be46cd` | ❌ (OKLink: manual upload only) |
| Worldchain | 480 | [`0x00000000d714EA34028930b762E96bFBe50F42C2`](https://worldscan.org/address/0x00000000d714EA34028930b762E96bFBe50F42C2) | `0xcb2436774C3e191c85056d248EF4260ce5f27A9D` | ✅ |
| Soneium | 1868 | [`0x000000005aF66799D1a6317714D66800f9CA1406`](https://soneium.blockscout.com/address/0x000000005aF66799D1a6317714D66800f9CA1406) | `0x2bad8182c09f50c8318d769245bea52c32be46cd` | ✅ |
| Tempo | 4217 | [`0x00000000fc1E66C9f582566EAd00108e55F1c0C6`](https://explorer.tempo.xyz/address/0x00000000fc1E66C9f582566EAd00108e55F1c0C6) | `0xCFB43dC56B55bE9611deD8384201cECf06A9811b` | 🟡 Sourcify (explorer ingest unconfirmed) |
| Base | 8453 | [`0x000000008a8330B5d1F43A62Bf4C673A49f27ba0`](https://basescan.org/address/0x000000008a8330B5d1F43A62Bf4C673A49f27ba0) | `0x31FAfd4889FA1269F7a13A66eE0fB458f27D72A9` | ✅ |
| Arbitrum (legacy, **prod**) | 42161 | [`0xB274d5F4b833b61B340b654d600A864fB604a87c`](https://arbiscan.io/address/0xB274d5F4b833b61B340b654d600A864fB604a87c) | (see uniswapx-sdk) | ✅ (pre-existing) |
| Arbitrum (canonical, parked) | 42161 | [`0x000000005aF66799D1a6317714D66800f9CA1406`](https://arbiscan.io/address/0x000000005aF66799D1a6317714D66800f9CA1406) | `0x2bad8182c09f50c8318d769245bea52c32be46cd` | ✅ |
| Celo | 42220 | [`0x00000000B8077fdf2281A80bE96f6c282B5d943A`](https://celoscan.io/address/0x00000000B8077fdf2281A80bE96f6c282B5d943A) | `0x0Eb863541278308c3A64F8E908BC646e27BFD071` | ✅ |
| Avalanche | 43114 | [`0x00000000862cCF095823fc7576Fa6C7e6b7385ef`](https://snowtrace.io/address/0x00000000862cCF095823fc7576Fa6C7e6b7385ef) | `0xeb0BCF27D1Fb4b25e708fBB815c421Aeb51eA9fc` | ✅ |
| Linea | 59144 | (deferred — no v4 PoolManager yet) | — | — |
| Blast | 81457 | [`0x0000000086f50C5E1a2500602183D4390A7FFc98`](https://blastscan.io/address/0x0000000086f50C5E1a2500602183D4390A7FFc98) | `0x2339C0d23b60739B3E5ABF201F05903D24A26C77` | ✅ |
| Zora | 7777777 | [`0x000000002C9A3812e15cf233190992E9a57EDB56`](https://explorer.zora.energy/address/0x000000002C9A3812e15cf233190992E9a57EDB56) | `0x36eEC182D0B24Df3DC23115D64DB521A93D5154f` | ✅ |

### Notes on the canonical-address chains

Four chains converge on the same reactor address `0x000000005aF66799D1a6317714D66800f9CA1406`:
**Unichain, XLayer, Soneium, Arbitrum** (parked). Each has the same v4
`PoolManager.owner()` value `0x2bad8182c09f50c8318d769245bea52c32be46cd`, so
the same `(salt, owner, bytecode)` tuple produces the same CREATE2 address
across chains. This is the original "canonical Tempo salt" mined for the
ECO-365 phase 1b deployment and reused here.

### Notes on Arbitrum

The legacy reactor at `0xB274d5F4b833b61B340b654d600A864fB604a87c` remains the
**production** reactor — registered in `uniswapx-sdk` and routing live traffic.
Do not switch routing to the new canonical-address reactor at
`0x000000005aF66799D1a6317714D66800f9CA1406` until a deliberate SDK migration
is planned.

### Notes on Tempo

The original Tempo deploy from ECO-365 phase 1b at
`0x000000005aF66799D1a6317714D66800f9CA1406` had `protocolFeeOwner` set to
`0x2bad...46cd`, which does **not** match Tempo's v4 `PoolManager.owner()`
(`0xCFB43dC56B55bE9611deD8384201cECf06A9811b`). The new redeploy at
`0x00000000fc1E66C9f582566EAd00108e55F1c0C6` is the production Tempo reactor;
the old reactor remains on-chain but inert (do not route to it).

## Transaction hashes

| Chain | ID | Tx hash |
|---|---|---|
| Mainnet | 1 | `0xbc038f17af40f47314fcadbfdaec2ce8fcc84a5f392a9092c6c441e8a143afa0` |
| Optimism | 10 | `0x60bd63640fc40ba5248060e0f2520ed47e64c7a5864d168ab99cde107f4df984` |
| BNB | 56 | `0xaf103098f478d0195d852e8cd009333edad0c7a73d8d97255264cecd2cce1bcc` |
| Unichain | 130 | `0xe377cc75b5ba2144e939d0c3ecf77a96fd9b1785aaab0b9b368828c9db90eaea` |
| Polygon | 137 | `0xe3419102fa71ca82ab63e68dea6e5a555b4117359778a662369d90ac25748fc3` |
| Monad | 143 | `0x3b745a3e7ddf28b42302eff6059ee8ed08772436b34462b3bdc0d4ddb0093b7f` |
| XLayer | 196 | `0x98f6c6013c2e0619e9b951c61e784cb3b17c4c584a8598a9d8049ea2134150e6` |
| Worldchain | 480 | `0x540948dcd8e6b2dca528a1f562aafa579199ba6ee0ce0a8001cb0e05950117f4` |
| Soneium | 1868 | `0xcb5a9516b309b1ab2e12992058f2480b4773bbf5f851ea689331ab25c13b6dce` |
| Tempo | 4217 | `0x5e97c535dc39893f883c8c96ba29f49a7a911d6fd2c584c3b3e02ece1cedb92d` |
| Base | 8453 | `0xef1b4c1893bba99de9f5f56d1e2f0c9850424ecea2875ae16e95598ce9ab5d09` |
| Arbitrum (canonical, parked) | 42161 | `0x51040b09716b231d438301e17b22bacf8d10b83aecfdd674fcf7000a2a90f0b3` |
| Celo | 42220 | `0x02f1c4477908154ab7eac35d95757b57ba9ec04ec944b54c58667f03baf3b760` |
| Avalanche | 43114 | `0x1ee85f6ea0dc5b7c83f7e7a3d107391022dd1aee0f0fad8483f2b64a1c970afe` |
| Blast | 81457 | `0x54cf96c8a74a9142da93f8d88755aaafb3eb47815da9de3a3d2caaf6c500f9c6` |
| Zora | 7777777 | `0xa64c2743279f4c6d677a57488af1b97ca0c28401617c2f615e470a0c3e0d8570` |

## Integration test results

All 17 reactor instances were exercised with the V3 Dutch order integration
suite (`test/integration/V3DutchOrderIntegration.t.sol`) against their
respective chain's public RPC, fork pinned to current-block-minus-50:

```
FOUNDRY_RPC_URL=<chain rpc>
INTEGRATION_REACTOR=<reactor addr>
INTEGRATION_FORK_BLOCK=<recent block>
FOUNDRY_PROFILE=integration forge test --match-contract V3DutchOrderIntegrationTest
```

Each suite runs 6 tests across three tiers: sanity (reactor/quoter/permit2
have code, reactor bound to canonical Permit2), tier-2 (off-chain order
resolution via OrderQuoter), tier-3 (end-to-end fill round-trip).

Tier-2/3 deploy fresh `MockERC20`s on the fork as trade tokens (some chains'
native stablecoins use chain-specific opcodes that revert under Foundry's
local EVM). The `OrderQuoter` lens is the real on-chain instance at
`0x00000000a3db63Df9078cBF3dF88B4CAdD5a7F58` on every chain — the multi-chain
quoter deploy made the fork-deploy fallback that earlier versions of the
test had unnecessary.

Both Arbitrum reactors require a `vm.mockCall` on the ArbSys precompile
(`0x64`) since the reactor's `BlockNumberish` mixin captures chainid 42161
at deploy time and routes block-number reads through ArbSys, which
Foundry's local EVM doesn't implement.

| Chain | ID | Reactor | Tests |
|---|---|---|---|
| Mainnet | 1 | `0x0000000015757c461808EA25Eb309638B62681cf` | ✅ 6/6 |
| Optimism | 10 | `0x000000000923439A92daE8930613568824108631` | ✅ 6/6 |
| BNB | 56 | `0x00000000a55e50C71b70Db3C8B58749cd1E18eB2` | ✅ 6/6 |
| Unichain | 130 | `0x000000005aF66799D1a6317714D66800f9CA1406` | ✅ 6/6 |
| Polygon | 137 | `0x00000000bAB6E234db8AD638B6A6395b7c499Bc4` | ✅ 6/6 |
| Monad | 143 | `0x000000000Ac008F7e07210CFb6648e40249232c2` | ✅ 6/6 |
| XLayer | 196 | `0x000000005aF66799D1a6317714D66800f9CA1406` | ✅ 6/6 |
| Worldchain | 480 | `0x00000000d714EA34028930b762E96bFBe50F42C2` | ✅ 6/6 |
| Soneium | 1868 | `0x000000005aF66799D1a6317714D66800f9CA1406` | ✅ 6/6 |
| Tempo | 4217 | `0x00000000fc1E66C9f582566EAd00108e55F1c0C6` | ✅ 6/6 |
| Base | 8453 | `0x000000008a8330B5d1F43A62Bf4C673A49f27ba0` | ✅ 6/6 |
| Arbitrum (canonical, parked) | 42161 | `0x000000005aF66799D1a6317714D66800f9CA1406` | ✅ 6/6 |
| Arbitrum (legacy, prod) | 42161 | `0xB274d5F4b833b61B340b654d600A864fB604a87c` | ✅ 6/6 |
| Celo | 42220 | `0x00000000B8077fdf2281A80bE96f6c282B5d943A` | ✅ 6/6 |
| Avalanche | 43114 | `0x00000000862cCF095823fc7576Fa6C7e6b7385ef` | ✅ 6/6 |
| Blast | 81457 | `0x0000000086f50C5E1a2500602183D4390A7FFc98` | ✅ 6/6 |
| Zora | 7777777 | `0x000000002C9A3812e15cf233190992E9a57EDB56` | ✅ 6/6 |

All sanity, off-chain quote, and end-to-end fill paths verified against
each deployed reactor on its native chain.

## Block explorer verification

Verification status (authoritative — confirmed via Etherscan V2 API on
2026-05-07):

**Verified on respective explorer (15 of 16 chains):**
- Etherscan family (12 chains, pushed via Etherscan V2 unified API): Mainnet,
  Optimism, BNB, Unichain, Polygon, Monad, Worldchain, Base, Arbitrum
  (canonical), Celo, Avalanche, Blast.
- Blockscout family (2 chains, picked up from Sourcify push): Soneium, Zora.
- Pre-existing: Arbitrum legacy `0xB274d5F4...` (Etherscan, original deploy).

**Tempo (4217):** source code is on Sourcify (perfect match) but Tempo's
explorer doesn't expose a verification API, so explorer-side ingest can't be
programmatically confirmed. Spot-check at
`explorer.tempo.xyz` before considering it fully verified.

**XLayer (196): unverified.** OKLink doesn't accept Etherscan-style API
submissions; source must be uploaded via the OKLink portal:
[docs](https://www.oklink.com/docs/en/#verify-contract).

### Useful commands

Re-check status across all Etherscan-family chains (uses `ETHERSCAN_API_KEY`
from `.env` — V2 unified key works for all listed chains except XLayer/Tempo):

```bash
curl "https://api.etherscan.io/v2/api?chainid=<id>&module=contract&action=getsourcecode&address=<addr>&apikey=$ETHERSCAN_API_KEY"
```

To re-push verification on any chain:

```bash
# Etherscan-family (with --chain registered in forge):
forge verify-contract --chain <chainId> \
  --etherscan-api-key $ETHERSCAN_API_KEY --watch \
  --constructor-args $(cast abi-encode "constructor(address,address)" \
    0x000000000022D473030F116dDEE9F6B43aC78BA3 <owner-from-table-above>) \
  <reactor-address> \
  src/reactors/V3DutchOrderReactor.sol:V3DutchOrderReactor

# Etherscan V2 chains not yet in forge's registry (Monad and similar):
forge verify-contract \
  --verifier etherscan \
  --verifier-url "https://api.etherscan.io/v2/api?chainid=<chainId>" \
  --etherscan-api-key $ETHERSCAN_API_KEY --watch \
  --constructor-args $(cast abi-encode "constructor(address,address)" \
    0x000000000022D473030F116dDEE9F6B43aC78BA3 <owner-from-table-above>) \
  <reactor-address> \
  src/reactors/V3DutchOrderReactor.sol:V3DutchOrderReactor

# Sourcify (Blockscout-integrated chains: Soneium, Zora, Worldchain, etc.):
forge verify-contract --chain <chainId> --verifier sourcify --watch \
  --constructor-args ... <addr> <contract>
```
