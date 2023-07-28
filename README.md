# UniswapX

[![Integration Tests](https://github.com/Uniswap/uniswapx/actions/workflows/test-integration.yml/badge.svg)](https://github.com/Uniswap/uniswapx/actions/workflows/test-integration.yml)
[![Unit Tests](https://github.com/Uniswap/uniswapx/actions/workflows/test.yml/badge.svg)](https://github.com/Uniswap/uniswapx/actions/workflows/test.yml)

UniswapX is an ERC20 swap settlement protocol that provides swappers with a gasless experience, MEV protection, and access to arbitrary liquidity sources. Swappers generate signed orders which specify the specification of their swap, and fillers compete using arbitrary fill strategies to satisfy these orders.


## UniswapX Protocol Architecture

![Architecture](./assets/uniswapx-architecture.png)

### Reactors

Order Reactors _settle_ UniswapX orders. They are responsible for validating orders of a specific type, resolving them into inputs and outputs, and executing them against the filler's strategy, and verifying that the order was successfully fulfilled.

Reactors process orders using the following steps:
- Validate the order
- Resolve the order into inputs and outputs
- Pull input tokens from the swapper to the fillContract using permit2 `permitWitnessTransferFrom` with the order as witness
- Call `reactorCallback` on the fillContract
- Transfer output tokens from the fillContract to the output recipients

Reactors implement the [IReactor](./src/interfaces/IReactor.sol) interface which abstracts the specifics of the order specification. This allows for different reactor implementations with different order formats to be used with the same interface, allowing for shared infrastructure and easy extension by fillers.

Current reactor implementations:
- [LimitOrderReactor](./src/reactors/LimitOrderReactor.sol): A reactor that settles simple static limit orders
- [DutchOrderReactor](./src/reactors/DutchOrderReactor.sol): A reactor that settles linear-decay dutch orders
- [ExclusiveDutchOrderReactor](./src/reactors/ExclusiveDutchOrderReactor.sol): A reactor that settles linear-decay dutch orders with a period of exclusivity before decay begins

### Fill Contracts

Order fillContracts _fill_ UniswapX orders. They specify the filler's strategy for fulfilling orders and are called by the reactor with `reactorCallback` when using `executeWithCallback` or `executeBatchWithCallback`.

Some sample fillContract implementations are provided in this repository:
- [SwapRouter02Executor](./src/sample-executors/SwapRouter02Executor.sol): A fillContract that uses UniswapV2 and UniswapV3 via the SwapRouter02 router

### Direct Fill

If a filler wants to simply fill orders using funds held by an address rather than using a fillContract strategy, they can do so gas efficiently by using `execute` or `executeBatch`. These functions cause the reactor to skip the `reactorCallback` and simply pull tokens from the filler using `msg.sender`.

# Integrating with UniswapX
Jump to the docs for [Creating a Filler Integration](https://docs.uniswap.org/contracts/uniswapx/guides/createfiller).

# Deployment Addresses

| Contract                      | Address                                                                                                               | Source                                                                                                                    |
| ---                           | ---                                                                                                                   | ---                                                                                                                       |
| Exclusive Dutch Order Reactor | [0x6000da47483062A0D734Ba3dc7576Ce6A0B645C4](https://etherscan.io/address/0x6000da47483062A0D734Ba3dc7576Ce6A0B645C4) | [ExclusiveDutchOrderReactor](https://github.com/Uniswap/UniswapX/blob/v1.1.0/src/reactors/ExclusiveDutchOrderReactor.sol) |
| OrderQuoter                   | [0x54539967a06Fc0E3C3ED0ee320Eb67362D13C5fF](https://etherscan.io/address/0x54539967a06Fc0E3C3ED0ee320Eb67362D13C5fF) | [OrderQuoter](https://github.com/Uniswap/UniswapX/blob/v1.1.0/src/OrderQuoter.sol)                                        |
| Permit2                       | [0x000000000022D473030F116dDEE9F6B43aC78BA3](https://etherscan.io/address/0x000000000022D473030F116dDEE9F6B43aC78BA3) | [Permit2](https://github.com/Uniswap/permit2)                                                                             |

# Usage

```
# install dependencies
forge install

# compile contracts
forge build

# run unit tests
forge test

# run integration tests
FOUNDRY_PROFILE=integration forge test
```

# Fee-on-Transfer Disclaimer

Note that UniswapX handles fee-on-transfer tokens by transferring the amount specified to the recipient. This means that the actual amount received by the recipient will be _after_ fees.

# Audit

This codebase was audited by [ABDK](./audit/ABDK.pdf).

## Bug Bounty

This repository is subject to the Uniswap Labs Bug Bounty program, per the terms defined [here](https://uniswap.org/bug-bounty).
