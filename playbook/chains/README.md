# Per-chain DutchV3 rollout research

Research scratchpads for rolling UniswapX DutchV3 out to every chain
that the Uniswap AMM front-end currently supports. One file per chain;
each file follows §0 + §1 of [`../NEW_CHAIN.md`](../NEW_CHAIN.md).

The list below is filtered from `universe`'s `ORDERED_CHAINS` to EVM
production chains. Solana (non-EVM) and testnets are excluded. Arbitrum
and Tempo already have DutchV3 deployed; included here for reference
only.

| chain | id | status | file |
|---|---|---|---|
| Mainnet | 1 | ⏳ research | [mainnet.md](./mainnet.md) |
| Optimism | 10 | ⏳ research | [optimism.md](./optimism.md) |
| Rootstock | 30 | (not in front-end ORDERED_CHAINS; skipped) | — |
| BNB | 56 | ⏳ research | [bnb.md](./bnb.md) |
| Unichain | 130 | ⏳ research | [unichain.md](./unichain.md) |
| Polygon | 137 | ⏳ research | [polygon.md](./polygon.md) |
| Monad | 143 | ⏳ research | [monad.md](./monad.md) |
| XLayer | 196 | ⏳ research | [xlayer.md](./xlayer.md) |
| ZKSync | 324 | ⏳ research | [zksync.md](./zksync.md) |
| Worldchain | 480 | ⏳ research | [worldchain.md](./worldchain.md) |
| Soneium | 1868 | ⏳ research | [soneium.md](./soneium.md) |
| Tempo | 4217 | ✅ DutchV3 live (ECO-365) | (see [../NEW_CHAIN.md §6](../NEW_CHAIN.md)) |
| Robinhood | 4663 | 🟢 reactor + quoter deployed 2026-06-12 (post-`BlockNumberish`-4663 bytecode); service wiring pending | [robinhood.md](./robinhood.md) |
| Arc | 5042 | 🟢 reactor + quoter deployed 2026-06-12; service wiring pending | [arc.md](./arc.md) |
| Base | 8453 | ⏳ research | [base.md](./base.md) |
| Arbitrum | 42161 | ✅ DutchV3 live (Arbitrum was the first V3 chain) | (skip) |
| Celo | 42220 | ⏳ research | [celo.md](./celo.md) |
| Avalanche | 43114 | ⏳ research | [avalanche.md](./avalanche.md) |
| Linea | 59144 | ⏳ research | [linea.md](./linea.md) |
| Blast | 81457 | ⏳ research | [blast.md](./blast.md) |
| Zora | 7777777 | ⏳ research | [zora.md](./zora.md) |

## Status legend

- ✅ DutchV3 live and routing
- 🟢 Ready to deploy (Permit2 + Arachnid factory present, EVM standard)
- 🟡 Has caveats (sub-second blocks, non-standard opcode behavior, missing infra) — see file
- ⚠️ Blocked (missing Permit2 / Arachnid factory / RPC unreachable / non-EVM)
- ⏳ Research not yet done
