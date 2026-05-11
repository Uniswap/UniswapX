#!/usr/bin/env bash
# =============================================================================
# deploy-v3-multichain.sh — broadcast V3DutchOrderReactor to every chain in
# `playbook/chains/salts.json` where it isn't already live and the deployer
# wallet has enough native balance.
#
# Per-chain config (chainId, name, RPC default, v4 PoolManager, owner, salt,
# expectedReactor) lives in `playbook/chains/salts.json`. The owner is derived
# from the v4 PoolManager.owner() per chain so the V3 reactor's
# protocolFeeOwner matches the AMM's per-chain governance. The (salt,
# expectedReactor) pair is mined together via create2crunch against
# (PERMIT2, owner). Chains where owner == 0x2bad...46cd reuse Tempo's
# canonical mined salt and converge on 0x000000005aF6...
#
# Per chain, runs preconditions before broadcasting (in this order):
#   1. RPC reachable + correct chainId.
#   2. salts.json has non-null (salt, expectedReactor) for the chain. If null,
#      the chain hasn't been mined yet — SKIP-NEEDS-MINING.
#   3. PoolManager.owner() at runtime matches salts.json `owner` exactly. If
#      the AMM owner has rotated since the salt was mined, the deploy would
#      use a stale owner — SKIP-OWNER-DRIFT.
#   4. expectedReactor address has no code yet (idempotent skip).
#   5. Permit2 deployed AND functional (DOMAIN_SEPARATOR returns non-zero).
#   6. Canonical Arachnid CREATE2 factory deployed.
#   7. Deployer wallet native balance >= MIN_BALANCE_WEI.
#   8. Owner-address sanity: WARN if FOUNDRY_REACTOR_OWNER is an EOA on this
#      chain (expected: multisig). Do not block.
#   9. Simulated forge-script run (no --broadcast) including the in-script
#      `predicted == V3_REACTOR_EXPECTED` runtime assertion. Catches bytecode
#      drift, factory issues, gas shortfalls before paying real gas.
#
# Skip list:
#   - zkSync Era (324): zksolc + non-EVM CREATE2 derivation; not in
#     salts.json. See playbook/chains/zksync.md.
#   - Linea (59144): no v4 PoolManager deployed → no PoolManager.owner() to
#     derive from. salts.json has the chain entry with `owner: null` and
#     this script treats null-owner chains as SKIP-NO-POOLMANAGER.
#
# Required env:
#   DEPLOYER_MNEMONIC            BIP-39 seed phrase for the deployer wallet
#
# Optional env:
#   DEPLOYER_MNEMONIC_INDEX      HD derivation index (default 0)
#   DRY_RUN=1                    runs all preconditions and the simulation,
#                                stops short of broadcasting.
#   MIN_BALANCE_WEI=<value>      default 5e16 (~0.05 ETH-equivalent).
#   RPC_<chainId>=<url>          override the public RPC for a chain.
#   SALTS_JSON=<path>            override salts.json path
#                                (default: playbook/chains/salts.json).
#
# Usage:
#   DEPLOYER_MNEMONIC="word1 word2 ..." ./scripts/deploy-v3-multichain.sh
#   DRY_RUN=1 DEPLOYER_MNEMONIC="word1 word2 ..." ./scripts/deploy-v3-multichain.sh
# =============================================================================

set -uo pipefail

# Resolve the repo root regardless of where the script is invoked from, so the
# relative `script/DeployDutchV3.s.sol` path resolves correctly.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}/.."

PERMIT2=0x000000000022D473030F116dDEE9F6B43aC78BA3
ARACHNID=0x4e59b44847b379578588920cA78FbF26c0B4956C
SALTS_JSON=${SALTS_JSON:-playbook/chains/salts.json}
MIN_BALANCE_WEI=${MIN_BALANCE_WEI:-50000000000000000} # ~0.05 ETH-equivalent
DRY_RUN=${DRY_RUN:-0}

# Default RPCs per chain. Override with RPC_<chainId>=<url> at invocation time.
# Function-based lookup (instead of `declare -A`) so the script works under
# macOS's default bash 3.2 in addition to bash 4+.
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
    59144)    echo "https://rpc.linea.build" ;;
    81457)    echo "https://rpc.blast.io" ;;
    7777777)  echo "https://rpc.zora.energy" ;;
  esac
}

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

if [[ ! -f "$SALTS_JSON" ]]; then
  echo "salts file not found at $SALTS_JSON" >&2
  exit 1
fi

DEPLOYER=$(cast wallet address --mnemonic "$DEPLOYER_MNEMONIC" --mnemonic-index "$DEPLOYER_MNEMONIC_INDEX")
echo "Deployer:  $DEPLOYER"
echo "Salts:     $SALTS_JSON"
echo "Mode:      $([ "$DRY_RUN" = "1" ] && echo 'DRY RUN — no broadcast' || echo 'BROADCAST')"
echo "Threshold: $MIN_BALANCE_WEI wei (~$(python3 -c "print($MIN_BALANCE_WEI/1e18)") ETH-equivalent)"
echo ""

results=()

ge() { python3 -c "print(int('$1') >= int('$2'))" 2>/dev/null; }
lower() { echo "$1" | tr '[:upper:]' '[:lower:]'; }

# Iterate chain ids from salts.json sorted ascending.
chain_ids=$(jq -r '.chains | keys_unsorted[] | tonumber' "$SALTS_JSON" | sort -n)

for chainid in $chain_ids; do
  entry=$(jq -r ".chains[\"$chainid\"]" "$SALTS_JSON")
  name=$(echo "$entry" | jq -r '.name')
  pool_manager=$(echo "$entry" | jq -r '.poolManager // "null"')
  owner=$(echo "$entry" | jq -r '.owner // "null"')
  salt=$(echo "$entry" | jq -r '.salt // "null"')
  expected_reactor=$(echo "$entry" | jq -r '.expectedReactor // "null"')
  gas_mult=$(echo "$entry" | jq -r '.gasEstimateMultiplier // empty')

  override_var="RPC_${chainid}"
  rpc="${!override_var:-$(default_rpc "$chainid")}"
  if [[ -z "$rpc" ]]; then
    echo "=== $name ($chainid) ==="
    echo "  [SKIP] no default RPC and no RPC_$chainid override"
    results+=("$name|$chainid|SKIP-NO-RPC-CONFIG")
    continue
  fi

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

  # 2. salts.json must have salt + expectedReactor (mining done) and owner
  if [[ "$pool_manager" == "null" || -z "$pool_manager" ]]; then
    echo "  [SKIP] no v4 PoolManager configured for this chain (defer until v4 ships)"
    results+=("$name|$chainid|SKIP-NO-POOLMANAGER")
    continue
  fi
  if [[ "$owner" == "null" || -z "$owner" ]]; then
    echo "  [SKIP] owner not set in salts.json (probe failed at config time)"
    results+=("$name|$chainid|SKIP-NO-OWNER")
    continue
  fi
  if [[ "$salt" == "null" || "$expected_reactor" == "null" ]]; then
    echo "  [SKIP] salt + expectedReactor not yet mined (run scripts/mine-salt.sh $chainid)"
    results+=("$name|$chainid|SKIP-NEEDS-MINING")
    continue
  fi

  # 3. PoolManager.owner() at runtime must match salts.json `owner`. If the
  # AMM owner has rotated since mining, the salt is stale.
  observed_owner=$(cast call "$pool_manager" "owner()(address)" --rpc-url "$rpc" 2>/dev/null || echo "")
  if [[ -z "$observed_owner" ]]; then
    echo "  [SKIP] PoolManager.owner() lookup failed at $pool_manager"
    results+=("$name|$chainid|SKIP-POOLMANAGER-LOOKUP-FAILED")
    continue
  fi
  if [[ "$(lower "$observed_owner")" != "$(lower "$owner")" ]]; then
    echo "  [SKIP] owner drift: salts.json says $owner, runtime says $observed_owner"
    echo "    The AMM owner has rotated since mining. Re-mine: scripts/mine-salt.sh $chainid"
    results+=("$name|$chainid|SKIP-OWNER-DRIFT")
    continue
  fi

  # 4. Already deployed?
  reactor_code=$(cast code "$expected_reactor" --rpc-url "$rpc" 2>/dev/null || echo "0x")
  if [[ "$reactor_code" != "0x" && -n "$reactor_code" ]]; then
    echo "  [SKIP] reactor already deployed at $expected_reactor"
    results+=("$name|$chainid|SKIP-ALREADY-DEPLOYED")
    continue
  fi

  # 5a. Permit2 code present
  permit2_code=$(cast code "$PERMIT2" --rpc-url "$rpc" 2>/dev/null || echo "0x")
  if [[ "$permit2_code" == "0x" || -z "$permit2_code" ]]; then
    echo "  [SKIP] Permit2 not deployed at canonical address"
    results+=("$name|$chainid|SKIP-NO-PERMIT2")
    continue
  fi

  # 5b. Permit2 functional
  permit2_ds=$(cast call "$PERMIT2" "DOMAIN_SEPARATOR()(bytes32)" --rpc-url "$rpc" 2>/dev/null || echo "")
  if [[ -z "$permit2_ds" || "$permit2_ds" == "0x"$(printf '0%.0s' {1..64}) ]]; then
    echo "  [SKIP] Permit2.DOMAIN_SEPARATOR() did not return a valid bytes32 (squatter/non-ABI-compatible contract?)"
    results+=("$name|$chainid|SKIP-PERMIT2-INVALID")
    continue
  fi

  # 6. Arachnid factory present
  arachnid_code=$(cast code "$ARACHNID" --rpc-url "$rpc" 2>/dev/null || echo "0x")
  if [[ "$arachnid_code" == "0x" || -z "$arachnid_code" ]]; then
    echo "  [SKIP] Arachnid CREATE2 factory not deployed"
    results+=("$name|$chainid|SKIP-NO-ARACHNID")
    continue
  fi

  # 7. Wallet balance
  balance=$(cast balance "$DEPLOYER" --rpc-url "$rpc" 2>/dev/null || echo "0")
  if [[ -z "$balance" ]]; then balance=0; fi
  if [[ "$(ge "$balance" "$MIN_BALANCE_WEI")" != "True" ]]; then
    eth_balance=$(python3 -c "print(int('$balance')/1e18)" 2>/dev/null || echo "?")
    echo "  [SKIP] insufficient balance ($balance wei, ~${eth_balance} native; need >=${MIN_BALANCE_WEI})"
    results+=("$name|$chainid|SKIP-NO-FUNDS")
    continue
  fi
  eth_balance=$(python3 -c "print(int('$balance')/1e18)" 2>/dev/null || echo "?")
  echo "  owner:    $owner"
  echo "  expected: $expected_reactor"
  echo "  balance:  $balance wei (~${eth_balance} native)"

  # 8. Owner sanity (warn if EOA)
  owner_code=$(cast code "$owner" --rpc-url "$rpc" 2>/dev/null || echo "0x")
  if [[ "$owner_code" == "0x" || -z "$owner_code" ]]; then
    echo "  [WARN] owner $owner is an EOA on this chain (expected: multisig). Continuing."
  else
    echo "  owner type: contract (~$((${#owner_code}/2 - 1)) bytes of code)"
  fi

  # 9. Simulation
  # Per-chain gas-estimate multiplier (Tempo needs 500 for high gas/byte code
  # deposit cost; others use forge's default 130%). Read from salts.json.
  gas_args=()
  if [[ -n "$gas_mult" ]]; then
    gas_args+=(--gas-estimate-multiplier "$gas_mult")
    echo "  gas multiplier: ${gas_mult}% (override from salts.json)"
  fi
  sim_log="/tmp/deploy-v3-${name}-sim-$(date +%s).log"
  echo "  [SIMULATE] forking and running script (no broadcast)..."
  if ! FOUNDRY_REACTOR_OWNER="$owner" V3_REACTOR_SALT="$salt" V3_REACTOR_EXPECTED="$expected_reactor" V3_REACTOR_CHAIN_ID="$chainid" \
      forge script script/DeployDutchV3.s.sol \
        --rpc-url "$rpc" \
        --mnemonics "$DEPLOYER_MNEMONIC" \
        --mnemonic-indexes "$DEPLOYER_MNEMONIC_INDEX" \
        ${gas_args[@]+"${gas_args[@]}"} \
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

  if [[ "$DRY_RUN" == "1" ]]; then
    echo "  [DRY-RUN] would broadcast next"
    results+=("$name|$chainid|DRY-RUN-SIM-OK")
    continue
  fi

  # 10. Broadcast
  echo "  [DEPLOY] broadcasting..."
  log="/tmp/deploy-v3-${name}-$(date +%s).log"
  if FOUNDRY_REACTOR_OWNER="$owner" V3_REACTOR_SALT="$salt" V3_REACTOR_EXPECTED="$expected_reactor" V3_REACTOR_CHAIN_ID="$chainid" \
      forge script script/DeployDutchV3.s.sol \
        --rpc-url "$rpc" \
        --broadcast \
        --mnemonics "$DEPLOYER_MNEMONIC" \
        --mnemonic-indexes "$DEPLOYER_MNEMONIC_INDEX" \
        ${gas_args[@]+"${gas_args[@]}"} \
        >"$log" 2>&1 \
    && grep -q "ONCHAIN EXECUTION COMPLETE & SUCCESSFUL" "$log"; then
    echo "  [OK] reactor at $expected_reactor (log: $log)"
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

if printf '%s\n' "${results[@]}" | grep -qE '\|FAIL($|-)'; then
  exit 1
fi
exit 0
