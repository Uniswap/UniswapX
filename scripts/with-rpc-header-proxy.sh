#!/usr/bin/env bash
# with-rpc-header-proxy.sh — run a command with FOUNDRY_RPC_URL pointed at a
# local proxy that injects the x-internal-service-secret header onto every
# forwarded RPC request, then exec the command.
#
# Why this exists: some internal RPC endpoints (e.g. the backend gateway used
# by CI integration tests) now reject requests missing
# x-internal-service-secret. `cast` can send custom headers natively
# (--rpc-headers / ETH_RPC_HEADERS), but `forge test`'s forking
# (vm.createSelectFork) and `forge script --rpc-url` build their RPC provider
# straight from the URL string with no header support at all — confirmed by
# reading the Foundry source (crates/evm/core/src/fork/multi.rs,
# crates/script/src/{execute,broadcast}.rs all call
# get_http_provider(url)/ProviderBuilder::new(url) with no headers attached).
# scripts/rpc-header-proxy.py is a small local HTTP proxy that adds the
# header before forwarding, so pointing FOUNDRY_RPC_URL at 127.0.0.1 gets the
# header to the upstream endpoint regardless of which Foundry code path is
# making the request.
#
# Required env:
#   UPSTREAM_RPC_URL     the real RPC endpoint to forward to
#
# Optional env:
#   RPC_HEADER_SECRET    value for the x-internal-service-secret header. If
#                        unset, runs the command against UPSTREAM_RPC_URL
#                        directly (no proxy) — matches public-RPC/local-dev
#                        usage where no header is required.
#
# Usage:
#   UPSTREAM_RPC_URL=https://... RPC_HEADER_SECRET=... \
#     scripts/with-rpc-header-proxy.sh forge test -vvv

set -uo pipefail

if [[ -z "${UPSTREAM_RPC_URL:-}" ]]; then
  echo "UPSTREAM_RPC_URL not set" >&2
  exit 1
fi
if [[ $# -eq 0 ]]; then
  echo "usage: $0 <command> [args...]" >&2
  exit 1
fi

if [[ -z "${RPC_HEADER_SECRET:-}" ]]; then
  export FOUNDRY_RPC_URL="$UPSTREAM_RPC_URL"
  exec "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')

python3 "$SCRIPT_DIR/rpc-header-proxy.py" "$UPSTREAM_RPC_URL" "x-internal-service-secret" "$RPC_HEADER_SECRET" "$PORT" &
proxy_pid=$!
trap 'kill "$proxy_pid" 2>/dev/null' EXIT

# Wait for the proxy socket to accept connections (max ~5s).
ready=0
for _ in $(seq 1 50); do
  if ! kill -0 "$proxy_pid" 2>/dev/null; then
    echo "rpc-header-proxy.py exited before starting" >&2
    exit 1
  fi
  if (exec 3<>"/dev/tcp/127.0.0.1/${PORT}") 2>/dev/null; then
    exec 3>&-
    ready=1
    break
  fi
  sleep 0.1
done
if [[ "$ready" != "1" ]]; then
  echo "rpc-header-proxy.py did not become ready on port $PORT" >&2
  exit 1
fi

export FOUNDRY_RPC_URL="http://127.0.0.1:${PORT}"
"$@"
