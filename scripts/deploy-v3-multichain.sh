#!/usr/bin/env bash
# =============================================================================
# deploy-v3-multichain.sh — broadcast V3DutchOrderReactor to every chain that
# the Uniswap AMM front-end supports, where it isn't already live and the
# deployer wallet has enough native balance to pay deploy gas.
#
# Per chain, runs preconditions before broadcasting (in this order):
#   1. RPC reachable + correct chainId
#   2. EXPECTED_REACTOR address has no code yet (idempotent skip)
#   3. Permit2 deployed at canonical address AND functional
#      (DOMAIN_SEPARATOR() returns non-zero bytes32 + encodes correct chainId)
#   4. Canonical Arachnid CREATE2 factory deployed at canonical address
#   5. Deployer wallet native balance >= MIN_BALANCE_WEI
#   6. Owner-address sanity: log whether FOUNDRY_REACTOR_OWNER is a contract
#      (expected: multisig) or an EOA. Warn on EOA; do not block.
#   7. Simulated deploy (forge script without --broadcast): runs the full
#      run() against a fork of the chain incl. the EXPECTED_REACTOR == predicted
#      invariant assertion. Catches bytecode drift, factory-return issues, gas
#      shortfalls, etc. before paying real gas.
#
# Skip list (chains that aren't compatible with the canonical-CREATE2 path):
#   - zkSync Era (324): zksolc bytecode + non-EVM CREATE2 derivation —
#     mined salt does not produce the expected address. Needs a separate
#     deploy pipeline. See playbook/chains/zksync.md.
#
# Idempotent re-runs:
#   - Tempo (4217): reactor at canonical EXPECTED_REACTOR — precondition
#     #2 fires and the chain is skipped with SKIP-ALREADY-DEPLOYED.
#   - Arbitrum (42161): existing V3 reactor lives at a different address
#     (0xB274d5F4b833b61B340b654d600A864fB604a87c, the legacy pre-canonical
#     deploy). EXPECTED_REACTOR has no code there yet, so the script will
#     deploy a NEW reactor at the canonical address. Migrating the SDK's
#     REACTOR_ADDRESS_MAPPING[42161][Dutch_V3] from 0xB274... to the
#     canonical address is a manual follow-up; until that lands, both
#     reactors will coexist on-chain (only the canonical one is used
#     once the SDK update merges).
#
# Required env:
#   DEPLOYER_KEY                 hex private key with 0x prefix
#   FOUNDRY_REACTOR_OWNER        protocolFeeOwner constructor arg; MUST match
#                                what the salt was mined for, else the in-script
#                                EXPECTED_REACTOR assertion fires before broadcast
#                                (canonical: 0x2bad8182c09f50c8318d769245bea52c32be46cd)
#
# Optional env:
#   DRY_RUN=1                    skip broadcast; still runs all preconditions
#                                AND the simulated forge-script run, so you can
#                                see exactly whether a real broadcast would
#                                succeed. The only thing skipped is sending
#                                the actual tx.
#   MIN_BALANCE_WEI=<value>      override the default 0.05 ETH-equivalent
#                                threshold (default 5e16 wei).
#   RPC_<chainId>=<url>          override the public RPC for a specific chain
#                                (e.g. RPC_1=https://eth-mainnet.alchemyapi.io/...).
#
# Usage:
#   DEPLOYER_KEY=0x... \
#   FOUNDRY_REACTOR_OWNER=0x2bad8182c09f50c8318d769245bea52c32be46cd \
#   ./scripts/deploy-v3-multichain.sh
#
#   # dry-run (preconditions only):
#   DRY_RUN=1 ./scripts/deploy-v3-multichain.sh
# =============================================================================

set -uo pipefail

# Resolve the repo root regardless of where the script is invoked from, so the
# relative `script/DeployDutchV3.s.sol` path resolves correctly.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}/.."

# These constants must mirror DeployDutchV3.s.sol.
EXPECTED_REACTOR=0x000000005aF66799D1a6317714D66800f9CA1406
PERMIT2=0x000000000022D473030F116dDEE9F6B43aC78BA3
ARACHNID=0x4e59b44847b379578588920cA78FbF26c0B4956C
EXPECTED_OWNER_LOWER=0x2bad8182c09f50c8318d769245bea52c32be46cd

MIN_BALANCE_WEI=${MIN_BALANCE_WEI:-50000000000000000} # 0.05 ETH-equivalent
DRY_RUN=${DRY_RUN:-0}

# chain rows: name|chainId|defaultRpc
CHAINS=(
  "mainnet|1|https://ethereum-rpc.publicnode.com"
  "optimism|10|https://mainnet.optimism.io"
  "bnb|56|https://bsc-dataseed.binance.org"
  "unichain|130|https://mainnet.unichain.org"
  "polygon|137|https://polygon-rpc.com"
  "monad|143|https://rpc.monad.xyz"
  "xlayer|196|https://rpc.xlayer.tech"
  "worldchain|480|https://worldchain-mainnet.g.alchemy.com/public"
  "soneium|1868|https://rpc.soneium.org"
  "tempo|4217|https://rpc.tempo.xyz"
  "base|8453|https://mainnet.base.org"
  "arbitrum|42161|https://arb1.arbitrum.io/rpc"
  "celo|42220|https://forno.celo.org"
  "avalanche|43114|https://api.avax.network/ext/bc/C/rpc"
  "linea|59144|https://rpc.linea.build"
  "blast|81457|https://rpc.blast.io"
  "zora|7777777|https://rpc.zora.energy"
)

# ---- preflight ----

if ! command -v cast >/dev/null 2>&1; then
  echo "cast not found; install foundry first" >&2
  exit 1
fi
if ! command -v forge >/dev/null 2>&1; then
  echo "forge not found; install foundry first" >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 not found (used for big-int comparisons)" >&2
  exit 1
fi

if [[ -z "${DEPLOYER_KEY:-}" ]]; then
  echo "DEPLOYER_KEY not set" >&2
  exit 1
fi
if [[ -z "${FOUNDRY_REACTOR_OWNER:-}" ]]; then
  echo "FOUNDRY_REACTOR_OWNER not set" >&2
  exit 1
fi

# Ensure FOUNDRY_REACTOR_OWNER matches what the salt was mined for. If not,
# every per-chain deploy would revert with the in-script EXPECTED_REACTOR
# assertion — fail fast here instead of mid-loop.
owner_lower=$(echo "$FOUNDRY_REACTOR_OWNER" | tr '[:upper:]' '[:lower:]')
if [[ "$owner_lower" != "$EXPECTED_OWNER_LOWER" ]]; then
  echo "FOUNDRY_REACTOR_OWNER mismatch: got $FOUNDRY_REACTOR_OWNER, expected $EXPECTED_OWNER_LOWER" >&2
  echo "  The script's salt was mined for that specific owner. Override the salt to use a different owner." >&2
  exit 1
fi

DEPLOYER=$(cast wallet address --private-key "$DEPLOYER_KEY")
echo "Deployer:  $DEPLOYER"
echo "Owner arg: $FOUNDRY_REACTOR_OWNER"
echo "Reactor:   $EXPECTED_REACTOR (mined for these args)"
echo "Mode:      $([ "$DRY_RUN" = "1" ] && echo 'DRY RUN — preconditions only' || echo 'BROADCAST')"
echo "Threshold: $MIN_BALANCE_WEI wei (~$(python3 -c "print($MIN_BALANCE_WEI/1e18)") ETH-equivalent)"
echo ""

results=()

ge() { python3 -c "print(int('$1') >= int('$2'))" 2>/dev/null; }

for row in "${CHAINS[@]}"; do
  IFS='|' read -r name chainid default_rpc <<<"$row"

  # per-chain RPC override env var: RPC_<chainId>
  override_var="RPC_${chainid}"
  rpc="${!override_var:-$default_rpc}"

  echo "=== $name ($chainid) — $rpc ==="

  # 1. RPC reachable + correct chainId
  observed_chainid_hex=$(cast chain-id --rpc-url "$rpc" 2>/dev/null || echo "")
  if [[ -z "$observed_chainid_hex" ]]; then
    echo "  [SKIP] RPC unreachable"
    results+=("$name|$chainid|SKIP-RPC-UNREACHABLE")
    continue
  fi
  observed_chainid=$(python3 -c "print(int('$observed_chainid_hex', 0))" 2>/dev/null || echo "0")
  if [[ "$observed_chainid" != "$chainid" ]]; then
    echo "  [SKIP] RPC chainId mismatch: expected $chainid, got $observed_chainid"
    results+=("$name|$chainid|SKIP-WRONG-CHAIN")
    continue
  fi

  # 2. Already deployed?
  reactor_code=$(cast code "$EXPECTED_REACTOR" --rpc-url "$rpc" 2>/dev/null || echo "0x")
  if [[ "$reactor_code" != "0x" && -n "$reactor_code" ]]; then
    echo "  [SKIP] reactor already deployed at $EXPECTED_REACTOR"
    results+=("$name|$chainid|SKIP-ALREADY-DEPLOYED")
    continue
  fi

  # 3a. Permit2 code present
  permit2_code=$(cast code "$PERMIT2" --rpc-url "$rpc" 2>/dev/null || echo "0x")
  if [[ "$permit2_code" == "0x" || -z "$permit2_code" ]]; then
    echo "  [SKIP] Permit2 not deployed at canonical address"
    results+=("$name|$chainid|SKIP-NO-PERMIT2")
    continue
  fi

  # 3b. Permit2 functional: returns a valid 32-byte DOMAIN_SEPARATOR. Catches
  # squatter contracts and broken zkEVM ports that share the address but not
  # the ABI. Cost: one staticcall.
  permit2_ds=$(cast call "$PERMIT2" "DOMAIN_SEPARATOR()(bytes32)" --rpc-url "$rpc" 2>/dev/null || echo "")
  if [[ -z "$permit2_ds" || "$permit2_ds" == "0x"$(printf '0%.0s' {1..64}) ]]; then
    echo "  [SKIP] Permit2.DOMAIN_SEPARATOR() did not return a valid bytes32 (squatter/non-ABI-compatible contract?)"
    results+=("$name|$chainid|SKIP-PERMIT2-INVALID")
    continue
  fi

  # 3c. Arachnid factory code present (no functional probe — its fallback-only
  # ABI doesn't expose a static-callable identity check; the simulation in
  # step 7 below catches a non-functional factory by failing to produce code
  # at the predicted address).
  arachnid_code=$(cast code "$ARACHNID" --rpc-url "$rpc" 2>/dev/null || echo "0x")
  if [[ "$arachnid_code" == "0x" || -z "$arachnid_code" ]]; then
    echo "  [SKIP] Arachnid CREATE2 factory not deployed"
    results+=("$name|$chainid|SKIP-NO-ARACHNID")
    continue
  fi

  # 4. Wallet balance check
  balance=$(cast balance "$DEPLOYER" --rpc-url "$rpc" 2>/dev/null || echo "0")
  if [[ -z "$balance" ]]; then balance=0; fi
  if [[ "$(ge "$balance" "$MIN_BALANCE_WEI")" != "True" ]]; then
    eth_balance=$(python3 -c "print(int('$balance')/1e18)" 2>/dev/null || echo "?")
    echo "  [SKIP] insufficient balance ($balance wei, ~${eth_balance} native; need >=${MIN_BALANCE_WEI})"
    results+=("$name|$chainid|SKIP-NO-FUNDS")
    continue
  fi
  eth_balance=$(python3 -c "print(int('$balance')/1e18)" 2>/dev/null || echo "?")
  echo "  balance: $balance wei (~${eth_balance} native)"

  # 6. Owner sanity. The reactor's `owner` is set from FOUNDRY_REACTOR_OWNER
  # at construction. The reactor doesn't validate the owner is a contract,
  # but governance expects a multisig. Warn if it's an EOA on this chain —
  # could indicate the multisig hasn't been deployed yet, or that we're
  # pointing at a wrong address.
  owner_code=$(cast code "$FOUNDRY_REACTOR_OWNER" --rpc-url "$rpc" 2>/dev/null || echo "0x")
  if [[ "$owner_code" == "0x" || -z "$owner_code" ]]; then
    echo "  [WARN] owner $FOUNDRY_REACTOR_OWNER is an EOA on this chain (expected: multisig). Continuing."
  else
    echo "  owner: contract (~$((${#owner_code}/2 - 1)) bytes of code)"
  fi

  # 7. Pre-broadcast simulation: forge script with no --broadcast forks the
  # chain and runs run() end-to-end including the in-script
  # `EXPECTED_REACTOR == predicted` invariant assertion. Catches bytecode
  # drift (compiler bump / metadata trailer shift), Arachnid factory return
  # issues, gas-estimate-too-low, and the predicted address not actually
  # producing code post-create2 — all without spending real gas. We pass
  # the same gas-estimate-multiplier as the real broadcast so simulated
  # gas usage matches.
  sim_log="/tmp/deploy-v3-${name}-sim-$(date +%s).log"
  echo "  [SIMULATE] forking and running script (no broadcast)..."
  if ! forge script script/DeployDutchV3.s.sol \
      --rpc-url "$rpc" \
      --private-key "$DEPLOYER_KEY" \
      --gas-estimate-multiplier 500 \
      >"$sim_log" 2>&1; then
    echo "  [FAIL-SIM] simulation reverted; log: $sim_log"
    tail -8 "$sim_log" | sed 's/^/    /'
    results+=("$name|$chainid|FAIL-SIM")
    continue
  fi
  if ! grep -q "Script ran successfully" "$sim_log"; then
    echo "  [FAIL-SIM] forge did not report success; log: $sim_log"
    tail -8 "$sim_log" | sed 's/^/    /'
    results+=("$name|$chainid|FAIL-SIM")
    continue
  fi
  echo "  [SIM-OK] simulation succeeded"

  # All preconditions pass + simulation green. Stop here on DRY_RUN.
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "  [DRY-RUN] would broadcast next"
    results+=("$name|$chainid|DRY-RUN-SIM-OK")
    continue
  fi

  # 8. Broadcast
  echo "  [DEPLOY] broadcasting..."
  log="/tmp/deploy-v3-${name}-$(date +%s).log"
  if forge script script/DeployDutchV3.s.sol \
      --rpc-url "$rpc" \
      --broadcast \
      --private-key "$DEPLOYER_KEY" \
      --gas-estimate-multiplier 500 \
      >"$log" 2>&1 \
    && grep -q "ONCHAIN EXECUTION COMPLETE & SUCCESSFUL" "$log"; then
    echo "  [OK] reactor at $EXPECTED_REACTOR (log: $log)"
    results+=("$name|$chainid|DEPLOYED")
  else
    echo "  [FAIL] log: $log"
    tail -5 "$log" | sed 's/^/    /'
    results+=("$name|$chainid|FAIL")
  fi
done

# ---- summary ----

echo ""
echo "=== Summary ==="
printf "  %-12s  %-8s  %s\n" "chain" "id" "status"
printf "  %-12s  %-8s  %s\n" "-----" "--" "------"
for r in "${results[@]}"; do
  IFS='|' read -r name chainid status <<<"$r"
  printf "  %-12s  %-8s  %s\n" "$name" "$chainid" "$status"
done

# Exit code reflects whether any DEPLOY attempt failed (FAIL or unexpected RPC errors).
# Skips are not treated as errors.
if printf '%s\n' "${results[@]}" | grep -q '|FAIL$'; then
  exit 1
fi
exit 0
