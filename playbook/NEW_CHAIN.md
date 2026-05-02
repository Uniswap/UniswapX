# UniswapX New-Chain Playbook

> Status: **scaffold**. This document captures the cross-repo work required to bring up UniswapX on a new chain. It will be filled in as the Tempo (chainId 4217) rollout completes; sections below are placeholders.

## Overview

_TBD — high-level description of what "supporting a new chain" means for UniswapX, the order types involved (V2/V3/Priority/Limit), and the typical rollout phases (testing, cosigner integration, executor onboarding, public launch)._

## Prereqs Checklist

_TBD — items to verify before starting:_

- [ ] Permit2 deployed at the canonical address (`0x000000000022D473030F116dDEE9F6B43aC78BA3`).
- [ ] Chain RPC + chainId confirmed.
- [ ] Block time, finality, and reorg characteristics documented.
- [ ] Native token semantics (or absence thereof) understood.
- [ ] `block.number` / `block.basefee` / `block.timestamp` semantics audited.
- [ ] `CALLVALUE` / `BALANCE` / `SELFBALANCE` opcode semantics confirmed.
- [ ] Routing/aggregation surfaces (UniversalRouter, SwapRouter02, etc.) availability documented.

## Per-Repo Changes

The UniswapX rollout spans roughly 7 repos. Each entry below is a placeholder and will be linked to the concrete PRs / changes once they land.

1. **`x-contracts`** (this repo) — reactor deploy script, README chain-specific notes, executor compatibility notes. _TBD._
2. **`x-parameterization-api`** — chain-specific cosigner parameterization (gas adjustment knobs, decay curves, exclusivity). _TBD._
3. **`x-service`** — order intake / quoting service routing. _TBD._
4. **`uniswapx-sdk`** — chainId constants, ABI bindings, helper exports. _TBD._
5. **`unified-routing-api`** — quote/route fan-out and chain enablement. _TBD._
6. **`trading-api`** — public quote/order endpoints, chain enablement flags. _TBD._
7. **`contracts`** (orchestration) — production deploy pipeline, addresses registry, verification. _TBD._

## EVM Quirks Audit

_TBD — checklist of EVM behaviors that have historically broken assumptions in UniswapX. Each item should be answered "standard" / "non-standard (details)" for the target chain._

- `block.number` semantics (monotonic? per slot? L1 vs L2?).
- `block.basefee` semantics (dynamic? constant? denominated in what unit?).
- `block.timestamp` granularity and monotonicity.
- Native token presence and `msg.value` flow.
- `CALLVALUE` / `BALANCE` / `SELFBALANCE` behavior.
- `BLOCKHASH`, `PREVRANDAO` availability.
- Precompile availability (`ecrecover`, etc.).
- Permit2 deployment status.
- EIP-1559 / typed-transaction support.
- Reorg depth and finality model.

## Rollout Plan

_TBD — staged rollout template:_

1. Internal testing on chain testnet / shadow environment.
2. Cosigner parameterization tuned and validated against on-chain conditions.
3. Limited executor onboarding (Uniswap-operated filler only).
4. Third-party PMM/filler onboarding with chain-specific executor guidance.
5. Public launch through trading-api.
6. Post-launch monitoring + feedback loop.
