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

## Required Secrets

- `RPC_URL` - Required for integration tests (mainnet fork)

## Security

Uses bullfrog egress policy in audit mode for network security monitoring.

## Auto-Update Instructions

Run `/update-claude-md .github/workflows` after workflow changes.
