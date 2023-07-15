# Integrating as a Filler

There are three components to integrating as a filler: defining a filler execution strategy, retrieving & executing discovered orders and enrolling in the UniswapX RFQ program.

## 1. Defining a Filler Execution Strategy

To execute a discovered order, a filler needs to call one of the `execute` methods ([source](https://github.com/Uniswap/UniswapX/blob/de36900fa074784bda215b902d4854bdffab09ba/src/reactors/BaseReactor.sol#L31)) of the Dutch Order Reactor, providing it with the orders to execute along with the address of the executor contract that defines their fill strategy.

The simplest fill strategy is called `Direct Filler`, where the trade is executed directly against tokens held in the fillers address. To use this strategy, we’ve provided a short cut so fillers do not need to deploy an executor contract. They can simply call `execute` with filler address `address(1)` to fill against themselves (see [source](https://github.com/Uniswap/UniswapX/blob/de36900fa074784bda215b902d4854bdffab09ba/src/reactors/BaseReactor.sol#L73)):

```solidity
// Execute direct filler order
DutchOrderReactor.execute(order, address(1));
```

More sophisticated fillers can implement arbitrarily complex strategies by deploying their own Executor contracts. This contract should implement the [IReactorCallback](https://github.com/Uniswap/UniswapX/blob/main/src/interfaces/IReactorCallback.sol) interface, which takes in an order with input tokens and returns the allotted number of output tokens to the caller. To use an executor contract, fillers simply specify it’s address when calling `execute`:

```solidity
// Execute custom fill strategy
address executor = /* Address of deployed executor contract */ ;
bytes fillData = /* Call data to be sent to your executor contract */;
DutchOrderReactor.execute(order, executor, fillData);
```

For convenience, we’ve provided an [example Executor Contract](https://github.com/Uniswap/UniswapX/tree/main/src/sample-executors) which demonstrates how a filler could implement a strategy that executes a UniswapX order against a Uniswap V3 pool.

## 2. Retrieve & Execute Signed Orders

All signed orders created through the Uniswap UI will be available via the [UniswapX Orders Endpoint](https://6q5qkya37k.execute-api.us-east-2.amazonaws.com/prod/api-docs). It’s up to the individual filler to architect their own systems for finding and executing profitable orders, but the basic flow is as follows:

1. Call `GET` on the `prod/dutch-auction/orders` of the UniswapX Orders Endpoint to retrieve open signed orders
2. Decode returned orders using the [UniswapX SDK](https://github.com/Uniswap/UniswapX-sdk/#parsing-orders)
3. Determine which orders you would like to execute
4. Send a new transaction to the [execute](https://github.com/Uniswap/UniswapX/blob/a2025e3306312fc284a29daebdcabb88b50037c2/src/reactors/BaseReactor.sol#L29) or [executeBatch](https://github.com/Uniswap/UniswapX/blob/a2025e3306312fc284a29daebdcabb88b50037c2/src/reactors/BaseReactor.sol#L37) methods of the [Dutch Order Reactor](https://github.com/Uniswap/UniswapX/blob/main/src/reactors/DutchOrderReactor.sol) specifying the signed orders you’d like to fill and the address of your executor contract

If the order is valid, it will be competing against other fillers attempts to execute it in a gas auction. For this reason, we recommend submitting these transactions through a service like [Flashbots Protect](https://docs.flashbots.net/flashbots-protect/overview).

# Parameterization on UniswapX

The UniswapX protocol does not explicitly parameterize the pricing of orders like the Exclusive Dutch Order, rather order parameterization is left to be configured by the order constructor. 

In the current Uniswap Labs interface implementation of UniswapX, some fillers may choose to help parameterize orders by participating as quoters. These fillers can *only* win a quote if they guarantee improved swapper execution over Uniswap v3 or v2 liquidity pools. Fillers who win a quote will receive execution priority for a limited period of time to fill orders they submitted wining quotes for. 

To ensure a smooth swapping experience for traders during the beta period, the set of Quoters will be vetted by Uniswap Labs following UniswapX’s launch, with plans to make the quoting system fully permissionless in the near future.

If you are interested in participating as a Quoter during the beta period, please reach out here.
