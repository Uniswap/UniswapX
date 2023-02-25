# What is Gouda?

[Gouda](https://github.com/uniswap/gouda) is an off-chain order execution protocol meant to generalize token swaps across liquidity sources and provide price improvement for users. “Swappers” generate signed messages specifying the terms of their trade, in the form of a linear-decay Dutch order. 

<p align="center">
<img width="575" alt="image" src="https://user-images.githubusercontent.com/8218221/216129758-df0ae2a3-05a7-44a2-bd79-0c7b1c10b8cb.png">
</p>

“Fillers" read these orders and execute them, taking input assets from the swapper and fulfilling output assets. Fillers are entitled to keep any spread or profits they are able to generate by fulfilling orders. [Build a filler integration](integration_guide.md).

## Gouda Order ***REMOVED***:

To Swappers on the Uniswap front end, Gouda orders look just like any other Uniswap order but behind the scenes they have a completely different flow. 
<p align="center">
<img width="787" alt="image" src="https://user-images.githubusercontent.com/8218221/216479887-9f2ae4b3-9225-4ee3-86d4-797118082c88.png">
</p>

1. A Gouda order starts with a swapper on a Uniswap front end requesting a quote by entering two tokens and an input or output amount
2. That request is sent to Gouda’s private network of RFQ Fillers who provide quotes for the proposed order. The best quote provided, is returned to the swapper on the Uniswap front end
3. The quote is transformed into a decaying Dutch Order by the Uniswap front end. It will decay over a preset number of blocks from the winning RFQ quote to Uniswap router price. If the swapper accepts the order they will sign it. 
4. The signed order is first broadcast to the winner of the RFQ. They will have a set a number of blocks to fill at their winning bid price
5. If the RFQ winner fades, the signed order is then broadcast publicly. Any filler is then able to compete to fill the order at the given price in its decay curve. 

## Gouda Protocol Architecture:

The Gouda Protocol uses two types of contract, **Order Reactors** and **Order Executors,** to allow a network of Fillers to execute signed orders created through the Uniswap front end and signed via [Permit2](https://github.com/Uniswap/permit2): 

<p align="center">
<img width="850" alt="image" src="https://user-images.githubusercontent.com/8218221/216130577-e7f9263b-b5a7-463a-b082-6b8bc4d7d41c.png">
</p>
  
**[Order Reactors](https://github.com/Uniswap/gouda/blob/main/src/interfaces/IReactor.sol)** are contracts that take in a specific type of order objects (like Dutch Orders), validate them, convert them to generic orders, and then execute them against a Filler’s Executor contract. 

The **[Dutch Limit Order Reactor](https://github.com/Uniswap/gouda/blob/main/src/reactors/DutchLimitOrderReactor.sol)** is Uniswaps Labs currently deployed reactor that allows execution of decaying Dutch Limit Orders created through Uniswaps interface. 

**[Order Executors](https://github.com/Uniswap/gouda/blob/main/src/interfaces/IReactorCallback.sol)** (called **[ReactorCallback](https://github.com/Uniswap/gouda/blob/main/src/interfaces/IReactorCallback.sol))** are contracts created by fillers that defines their individual execution strategy which will be called by the reactor, in order to execute requested orders (you can find sample executor contracts [here](https://github.com/Uniswap/gouda/tree/main/src/sample-executors))

# Integrating with Gouda
See [Filler Integration Guide](integration_guide.md)

# Helpful Links

| Name  | Description | Link |
| --- | --- | --- |
| Gouda Orders Endpoint | Publicly available endpoint for querying open Gouda Orders | https://nwktw6mvek.execute-api.us-east-2.amazonaws.com/prod/api-docs  |
| Order Creation UI | A test UI that allows you to create, sign and broadcast Gouda orders. |https://interface-gouda.vercel.app/ |
| Permit2 | Uniswap’s permit protocol used by swappers to sign orders.  | https://github.com/Uniswap/permit2 |


# Deployment Addresses

| Contract | Address | Source |
| --- | --- | --- |
| Dutch Limit Order Reactor | https://etherscan.io/address/0x81f570f48BE8d3D358404f257b5bDC4A88eefA50 | https://github.com/Uniswap/gouda/blob/main/src/reactors/DutchLimitOrderReactor.sol |
| Permit2 | https://etherscan.io/address/0x000000000022D473030F116dDEE9F6B43aC78BA3 | https://github.com/Uniswap/permit2  |


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
# Disclaimer
This is EXPERIMENTAL, UNAUDITED code. Do not use in production.
