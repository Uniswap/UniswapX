# Gouda
A generic off-chain order execution protocol. 

## Usage

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

## Protocol

![Architecture Diagram](./assets/gouda-architecture.png)

### Flow of an Order
1. A `maker` creates an order off-chain, specifying the assets and amounts they wish to trade
2. The `maker` signs the order with their private key
3. A `taker` sees the order, and looks for an optimal venue to execute it on
4. The `taker` submits the order to the `reactor`, specifying a `fillContract` which will fill the order
5. The reactor calls `PermitPost` to verify the `maker`'s signature and transfer their input tokens to the `fillContract`
6. The reactor passes control off to the `fillContract`
7. The `fillContract` uses the input tokens to acquire the required output tokens
8. The `reactor` finally remits the output tokens to the `maker`

## Disclaimer
This is EXPERIMENTAL, UNAUDITED code. Do not use in production.
