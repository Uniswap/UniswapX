#!/usr/bin/env bash
# =============================================================================
# mine-salt.sh — mine a CREATE2 salt for the V3DutchOrderReactor on one chain.
#
# Reads the chain's owner from playbook/chains/salts.json, computes the
# initcode hash for (PERMIT2, owner), runs create2crunch against the
# canonical Arachnid factory, picks the best candidate (≥TARGET_LEADING
# leading zero bytes, max total zeros as tiebreaker), and updates the
# chain's entry in salts.json with `salt`, `expectedReactor`, and `minedAt`.
#
# Per-chain working directory keeps each mining run's `efficient_addresses
# .txt` separate from the others — required for safe parallelism.
#
# Usage:
#   ./scripts/mine-salt.sh <chainId>                       # default 600s
#   LIMIT_SECONDS=300 ./scripts/mine-salt.sh <chainId>     # custom duration
#   TARGET_LEADING=5 ./scripts/mine-salt.sh <chainId>      # raise the bar
#
# Requires: forge build output up-to-date, create2crunch built, jq, python3.
# =============================================================================

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}/.."

CREATE2CRUNCH=${CREATE2CRUNCH:-/Users/cody.born/repos/create2crunch/target/release/create2crunch}
SALTS_JSON=${SALTS_JSON:-playbook/chains/salts.json}
PERMIT2_LOWER=000000000022d473030f116ddee9f6b43ac78ba3
ARACHNID=0x4e59b44847b379578588920cA78FbF26c0B4956C
TARGET_LEADING=${TARGET_LEADING:-4}
LIMIT_SECONDS=${LIMIT_SECONDS:-600}

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <chainId>" >&2
  exit 1
fi
chainid=$1

for cmd in cast jq python3 awk; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "[$chainid] missing dep: $cmd" >&2
    exit 1
  fi
done
if [[ ! -x "$CREATE2CRUNCH" ]]; then
  echo "[$chainid] create2crunch binary not found at $CREATE2CRUNCH" >&2
  exit 1
fi

owner=$(jq -r ".chains[\"$chainid\"].owner // \"null\"" "$SALTS_JSON")
name=$(jq -r ".chains[\"$chainid\"].name // \"chain-$chainid\"" "$SALTS_JSON")
existing_salt=$(jq -r ".chains[\"$chainid\"].salt // \"null\"" "$SALTS_JSON")

if [[ "$owner" == "null" ]]; then
  echo "[$chainid:$name] no owner in salts.json (probably no v4 PoolManager); skipping"
  exit 0
fi
if [[ "$existing_salt" != "null" ]]; then
  echo "[$chainid:$name] salt already set ($existing_salt); refusing to remine. Clear the field in salts.json to re-mine."
  exit 0
fi

owner_lower=$(echo "$owner" | tr '[:upper:]' '[:lower:]' | sed 's/^0x//')

# Build initcode = creationCode || abi.encode(IPermit2(PERMIT2), owner)
init_hex=$(python3 -c "
import json
with open('out/V3DutchOrderReactor.sol/V3DutchOrderReactor.json') as f:
    a = json.load(f)
bc = a['bytecode']['object']
if bc.startswith('0x'): bc = bc[2:]
print('0x' + bc + ('0'*24 + '$PERMIT2_LOWER') + ('0'*24 + '$owner_lower'))
")
init_hash=$(cast keccak "$init_hex")

workdir=/tmp/mine-salt-$chainid
mkdir -p "$workdir"
rm -f "$workdir/efficient_addresses.txt"

start_ts=$(date +%s)
echo "[$(date +%H:%M:%S)] [$chainid:$name] mining $LIMIT_SECONDS s; owner=$owner; initcode_hash=$init_hash"

# Run create2crunch in the per-chain workdir; kill at LIMIT_SECONDS.
# macOS lacks `timeout`, so use a manual watchdog: launch the miner, run a
# detached killer that sleeps then SIGKILLs, wait for the miner to exit
# (either naturally killed or having spun on its own), then clean up the
# killer.
(
  cd "$workdir"
  "$CREATE2CRUNCH" "$ARACHNID" 0x0000000000000000000000000000000000000000 "$init_hash" \
    >/dev/null 2>&1 &
  crunch_pid=$!
  ( sleep "$LIMIT_SECONDS" && kill -9 "$crunch_pid" 2>/dev/null ) &
  killer_pid=$!
  wait "$crunch_pid" 2>/dev/null || true
  kill -9 "$killer_pid" 2>/dev/null || true
)

elapsed=$(( $(date +%s) - start_ts ))
candidates=$(wc -l < "$workdir/efficient_addresses.txt" 2>/dev/null || echo 0)
echo "[$(date +%H:%M:%S)] [$chainid:$name] mining ended after ${elapsed}s; $candidates raw candidates"

# Pick the best candidate: ≥TARGET_LEADING zero bytes, then most total zeros.
best_line=$(awk -F' => ' -v thr="$TARGET_LEADING" '
{
  s = substr($2, 3); n=0; total=0
  for (i=1; i<=length(s); i+=2) { if (substr(s,i,2)=="00") n++; else break }
  for (i=1; i<=length(s); i+=2) { if (substr(s,i,2)=="00") total++ }
  if (n >= thr) printf("%d\t%d\t%s\n", n, total, $0)
}' "$workdir/efficient_addresses.txt" 2>/dev/null | sort -t$'\t' -k1,1nr -k2,2nr | head -1)

if [[ -z "$best_line" ]]; then
  echo "[$chainid:$name] FAIL: no candidate with >=${TARGET_LEADING} leading zero bytes after ${elapsed}s. Re-run with longer LIMIT_SECONDS."
  exit 2
fi

leading=$(echo "$best_line" | awk -F'\t' '{print $1}')
total=$(echo "$best_line" | awk -F'\t' '{print $2}')
row=$(echo "$best_line" | awk -F'\t' '{print $3}')
salt=$(echo "$row" | awk -F' => ' '{print $1}')
addr=$(echo "$row" | awk -F' => ' '{print $2}')

# Verify via cast create2 — sanity check the salt actually produces the address.
predicted=$(cast create2 --deployer "$ARACHNID" --salt "$salt" --init-code-hash "$init_hash" 2>/dev/null)
if [[ "$(echo "$predicted" | tr '[:upper:]' '[:lower:]')" != "$(echo "$addr" | tr '[:upper:]' '[:lower:]')" ]]; then
  echo "[$chainid:$name] FAIL: predicted address $predicted does not match miner output $addr"
  exit 3
fi

echo "[$chainid:$name] WIN: $addr (${leading} leading + $((total - leading)) body = ${total} total zero bytes)"

# Update salts.json atomically. macOS doesn't ship flock; use `mkdir` as a
# portable mutex (the syscall is atomic on every supported FS — only the
# winning racer can create the directory). Spin until acquired.
lockdir=/tmp/mine-salt-salts-json.lockdir
while ! mkdir "$lockdir" 2>/dev/null; do sleep 0.1; done
trap 'rmdir "$lockdir" 2>/dev/null || true' EXIT
tmp=$(mktemp)
jq \
  --arg chainid "$chainid" \
  --arg salt "$salt" \
  --arg addr "$addr" \
  --arg minedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg leading "$leading" \
  --arg total "$total" \
  '.chains[$chainid].salt = $salt
   | .chains[$chainid].expectedReactor = $addr
   | .chains[$chainid].minedAt = $minedAt
   | .chains[$chainid].minedZeroBytes = ($leading + " leading + " + $total + " total")' \
  "$SALTS_JSON" > "$tmp" && mv "$tmp" "$SALTS_JSON"
rmdir "$lockdir" 2>/dev/null || true
trap - EXIT

# Preserve mining output for inspection.
mv "$workdir/efficient_addresses.txt" "$workdir/efficient_addresses.${chainid}.txt"

echo "[$chainid:$name] salts.json updated: salt=${salt:0:18}... expected=$addr"
