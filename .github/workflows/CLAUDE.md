# GitHub Workflows

## Overview

CI/CD workflows for automated testing on push to main and pull requests.

## Workflows

- **test.yml** (unit-test) - Runs unit tests with Foundry v1.1.0
- **test-integration.yml** (integration-test) - Runs integration tests with Foundry nightly

## Pipeline Steps

Both workflows:
1. Checkout with recursive submodules
2. Install Foundry toolchain
3. Build contracts (`forge build --sizes`)
4. Run tests (`forge test -vvv`)

Unit tests also run `forge fmt --check` and build calibur submodule first.

Integration tests run `forge test` through `scripts/with-rpc-header-proxy.sh`, which points `FOUNDRY_RPC_URL` at a local proxy (`scripts/rpc-header-proxy.py`) injecting the `x-internal-service-secret` header — the RPC endpoint requires it and Foundry's forking code has no native way to send custom headers.

## Required Secrets

- `RPC_URL` - Required for integration tests (mainnet fork); forwarded to the wrapper as `UPSTREAM_RPC_URL`
- `RPC_HEADER_SECRET` - Value sent as the `x-internal-service-secret` header on integration-test RPC calls

## Security

Uses bullfrog egress policy in audit mode for network security monitoring.

## Auto-Update Instructions

Run `/update-claude-md .github/workflows` after workflow changes.
