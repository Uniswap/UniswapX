#!/usr/bin/env bash
# =============================================================================
# deploy-quoter-multichain.sh — broadcast OrderQuoter to every chain in the
# AMM rollout where it's not already deployed.
#
# OrderQuoter has no constructor args, so the initcode is byte-identical
# across chains. With the canonical Arachnid CREATE2 factory and the salt
# already mined for the Tempo deploy (see script/DeployOrderQuoter.s.sol),
# the contract deploys to the SAME address on every chain — no per-chain
# mining, no salts.json registry needed. The fixed (salt, address) pair
# lives in DeployOrderQuoter.s.sol and is shared by every chain here.
#
# Per chain, runs preconditions before broadcasting (in this order):
#   1. RPC reachable + correct chainId.
#   2. EXPECTED_QUOTER address has no code yet (idempotent skip).
#   3. Canonical Arachnid CREATE2 factory deployed.
#   4. Deployer wallet native balance >= MIN_BALANCE_WEI.
#   5. Simulated forge-script run (no --broadcast) — catches bytecode drift
#      via DeployOrderQuoter.s.sol's `predicted == EXPECTED_QUOTER` assert
#      before paying real gas.
#
# Skip list:
#   - zkSync Era (324): zksolc + non-EVM CREATE2 derivation; not handled.
#   - Linea (59144): excluded from the V3 rollout (no v4 PoolManager); to
#     keep the quoter address uniform with the reactor rollout, we skip it
#     here too. Add later if/when Linea joins.
#
# Required env:
#   DEPLOYER_MNEMONIC            BIP-39 seed phrase for the deployer wallet
#
# Optional env:
#   DEPLOYER_MNEMONIC_INDEX      HD derivation index (default 0)
#   DRY_RUN=1                    runs preconditions + simulation, no broadcast
#   MIN_BALANCE_WEI=<value>      default 5e16 (~0.05 ETH-equivalent)
#   RPC_<chainId>=<url>          override the public RPC for a chain
#
# Usage:
#   DEPLOYER_MNEMONIC="word1 word2 ..." ./scripts/deploy-quoter-multichain.sh
#   DRY_RUN=1 DEPLOYER_MNEMONIC="word1 word2 ..." ./scripts/deploy-quoter-multichain.sh
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}/.."

ARACHNID=0x4e59b44847b379578588920cA78FbF26c0B4956C
EXPECTED_QUOTER=0x00000000a3db63Df9078cBF3dF88B4CAdD5a7F58
MIN_BALANCE_WEI=${MIN_BALANCE_WEI:-50000000000000000}
DRY_RUN=${DRY_RUN:-0}

# Default RPCs per chain; override with RPC_<chainId>=<url>. Function-based
# so the script works under bash 3.2 (macOS default).
default_rpc() {
  case "$1" in
    1)        echo "https://ethereum-rpc.publicnode.com" ;;
    10)       echo "https://mainnet.optimism.io" ;;
    56)       echo "https://bsc-dataseed.binance.org" ;;
    130)      echo "https://mainnet.unichain.org" ;;
    137)      echo "https://polygon-rpc.com" ;;
    143)      echo "https://rpc.monad.xyz" ;;
    196)      echo "https://rpc.xlayer.tech" ;;
    480)      echo "https://worldchain-mainnet.g.alchemy.com/public" ;;
    1868)     echo "https://rpc.soneium.org" ;;
    4217)     echo "https://rpc.tempo.xyz" ;;
    8453)     echo "https://mainnet.base.org" ;;
    42161)    echo "https://arb1.arbitrum.io/rpc" ;;
    42220)    echo "https://forno.celo.org" ;;
    43114)    echo "https://api.avax.network/ext/bc/C/rpc" ;;
    81457)    echo "https://rpc.blast.io" ;;
    7777777)  echo "https://rpc.zora.energy" ;;
  esac
}

# Per-chain gas-estimate-multiplier override (Tempo charges ~5x on code
# deposit). Empty = use forge default 130%.
gas_multiplier() {
  case "$1" in
    4217) echo "500" ;;
    *)    echo "" ;;
  esac
}

# Chains to deploy on. Linea (59144) deliberately excluded for parity with
# the V3 reactor rollout. zkSync (324) excluded — non-EVM CREATE2.
CHAINS="1 10 56 130 137 143 196 480 1868 4217 8453 42161 42220 43114 81457 7777777"

# ---- preflight ----

for cmd in cast forge python3 jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "$cmd not found; install it first" >&2
    exit 1
  fi
done

if [[ -z "${DEPLOYER_MNEMONIC:-}" ]]; then
  echo "DEPLOYER_MNEMONIC not set" >&2
  exit 1
fi
DEPLOYER_MNEMONIC_INDEX=${DEPLOYER_MNEMONIC_INDEX:-0}

DEPLOYER=$(cast wallet address --mnemonic "$DEPLOYER_MNEMONIC" --mnemonic-index "$DEPLOYER_MNEMONIC_INDEX")
echo "Deployer:        $DEPLOYER"
echo "Expected quoter: $EXPECTED_QUOTER (same on every chain)"
echo "Mode:            $([ "$DRY_RUN" = "1" ] && echo 'DRY RUN — no broadcast' || echo 'BROADCAST')"
echo "Threshold:       $MIN_BALANCE_WEI wei (~$(python3 -c "print($MIN_BALANCE_WEI/1e18)") ETH-equivalent)"
echo ""

results=()
ge() { python3 -c "print(int('$1') >= int('$2'))" 2>/dev/null; }

for chainid in $CHAINS; do
  override_var="RPC_${chainid}"
  rpc="${!override_var:-$(default_rpc "$chainid")}"
  if [[ -z "$rpc" ]]; then
    echo "=== chain $chainid ==="
    echo "  [SKIP] no RPC configured"
    results+=("$chainid|SKIP-NO-RPC")
    continue
  fi

  echo "=== chain $chainid — $rpc ==="

  # 1. RPC reachable + correct chainId
  observed_chainid_hex=$(cast chain-id --rpc-url "$rpc" 2>/dev/null || echo "")
  if [[ -z "$observed_chainid_hex" ]]; then
    echo "  [SKIP] RPC unreachable"
    results+=("$chainid|SKIP-RPC-UNREACHABLE")
    continue
  fi
  observed_chainid=$(python3 -c "print(int('$observed_chainid_hex', 0))" 2>/dev/null || echo "0")
  if [[ "$observed_chainid" != "$chainid" ]]; then
    echo "  [SKIP] RPC chainId mismatch: expected $chainid, got $observed_chainid"
    results+=("$chainid|SKIP-WRONG-CHAIN")
    continue
  fi

  # 2. Already deployed?
  quoter_code=$(cast code "$EXPECTED_QUOTER" --rpc-url "$rpc" 2>/dev/null || echo "0x")
  if [[ ${#quoter_code} -gt 4 ]]; then
    echo "  [SKIP] quoter already at $EXPECTED_QUOTER"
    results+=("$chainid|SKIP-ALREADY-DEPLOYED")
    continue
  fi

  # 3. Arachnid factory present
  arachnid_code=$(cast code "$ARACHNID" --rpc-url "$rpc" 2>/dev/null || echo "0x")
  if [[ ${#arachnid_code} -le 4 ]]; then
    echo "  [SKIP] Arachnid CREATE2 factory not deployed"
    results+=("$chainid|SKIP-NO-ARACHNID")
    continue
  fi

  # 4. Wallet balance
  balance=$(cast balance "$DEPLOYER" --rpc-url "$rpc" 2>/dev/null || echo "0")
  if [[ -z "$balance" ]]; then balance=0; fi
  if [[ "$(ge "$balance" "$MIN_BALANCE_WEI")" != "True" ]]; then
    eth_balance=$(python3 -c "print(int('$balance')/1e18)" 2>/dev/null || echo "?")
    echo "  [SKIP] insufficient balance ($balance wei, ~${eth_balance} native; need >=${MIN_BALANCE_WEI})"
    results+=("$chainid|SKIP-NO-FUNDS")
    continue
  fi
  eth_balance=$(python3 -c "print(int('$balance')/1e18)" 2>/dev/null || echo "?")
  echo "  balance:  $balance wei (~${eth_balance} native)"

  # 5. Per-chain gas multiplier
  gas_mult=$(gas_multiplier "$chainid")
  gas_args=()
  if [[ -n "$gas_mult" ]]; then
    gas_args+=(--gas-estimate-multiplier "$gas_mult")
    echo "  gas multiplier: ${gas_mult}% (override)"
  fi

  # 6. Simulation
  sim_log="/tmp/deploy-quoter-${chainid}-sim-$(date +%s).log"
  echo "  [SIMULATE] forking and running script (no broadcast)..."
  if ! forge script script/DeployOrderQuoter.s.sol \
        --rpc-url "$rpc" \
        --mnemonics "$DEPLOYER_MNEMONIC" \
        --mnemonic-indexes "$DEPLOYER_MNEMONIC_INDEX" \
        ${gas_args[@]+"${gas_args[@]}"} \
        >"$sim_log" 2>&1; then
    echo "  [FAIL-SIM] simulation reverted; log: $sim_log"
    tail -8 "$sim_log" | sed 's/^/    /'
    results+=("$chainid|FAIL-SIM")
    continue
  fi
  if ! grep -q "Script ran successfully" "$sim_log"; then
    echo "  [FAIL-SIM] forge did not report success; log: $sim_log"
    tail -8 "$sim_log" | sed 's/^/    /'
    results+=("$chainid|FAIL-SIM")
    continue
  fi
  echo "  [SIM-OK] simulation succeeded"

  if [[ "$DRY_RUN" == "1" ]]; then
    echo "  [DRY-RUN] would broadcast next"
    results+=("$chainid|DRY-RUN-SIM-OK")
    continue
  fi

  # 7. Broadcast
  echo "  [DEPLOY] broadcasting..."
  log="/tmp/deploy-quoter-${chainid}-$(date +%s).log"
  if forge script script/DeployOrderQuoter.s.sol \
        --rpc-url "$rpc" \
        --broadcast \
        --mnemonics "$DEPLOYER_MNEMONIC" \
        --mnemonic-indexes "$DEPLOYER_MNEMONIC_INDEX" \
        ${gas_args[@]+"${gas_args[@]}"} \
        >"$log" 2>&1 \
    && grep -q "ONCHAIN EXECUTION COMPLETE & SUCCESSFUL" "$log"; then
    echo "  [OK] quoter at $EXPECTED_QUOTER (log: $log)"
    results+=("$chainid|DEPLOYED")
  else
    echo "  [FAIL] log: $log"
    tail -5 "$log" | sed 's/^/    /'
    results+=("$chainid|FAIL")
  fi
done

# ---- summary ----

echo ""
echo "=== Summary (quoter @ $EXPECTED_QUOTER) ==="
printf "  %-8s  %s\n" "chainId" "status"
printf "  %-8s  %s\n" "-------" "------"
for r in "${results[@]}"; do
  IFS='|' read -r chainid status <<<"$r"
  printf "  %-8s  %s\n" "$chainid" "$status"
done

if printf '%s\n' "${results[@]}" | grep -qE '\|FAIL($|-)'; then
  exit 1
fi
exit 0
