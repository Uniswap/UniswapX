# UniswapX

## Overview

ERC20 swap settlement protocol providing gasless swaps, MEV protection, and arbitrary liquidity sources. Swappers sign orders; fillers compete to fulfill them.

## Commands

```bash
forge install          # Install dependencies
forge build            # Compile contracts
forge test             # Run unit tests
forge test -vvv        # Verbose test output
forge fmt              # Format code
forge fmt --check      # Check formatting
FOUNDRY_PROFILE=integration forge test  # Run integration tests
```

## Project Structure

- `src/` - Contract source code
  - `reactors/` - Order settlement reactors (Dutch, Limit, Priority, V2, V3)
  - `lib/` - Shared libraries (decay, order encoding, fees)
  - `interfaces/` - Contract interfaces
  - `sample-executors/` - Example filler implementations
  - `lens/` - OrderQuoter for off-chain simulation
- `test/` - Foundry tests (unit + integration)
- `script/` - Deployment scripts
- `lib/` - Git submodule dependencies

## Key Concepts

- **Reactors**: Validate, resolve, and settle orders via permit2
- **Fill Contracts**: Implement filler strategies via `reactorCallback`
- **Direct Fill**: Gas-efficient fills without callback using `execute`

## Dependencies

- **permit2** - Gasless token approvals
- **forge-std** - Foundry testing utilities
- **solmate** - Gas-optimized contracts
- **openzeppelin-contracts** - Security utilities
- **calibur** - Additional utilities

## Configuration

- Solidity 0.8.29, optimizer with 1M runs
- Integration tests require `FOUNDRY_RPC_URL` env var

## Auto-Update Instructions

Run `/update-claude-md` after code changes to sync documentation.
