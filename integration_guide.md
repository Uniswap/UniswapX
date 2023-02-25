# Integrating as a Filler

There are three components to integrating as a filler: defining a filler execution strategy, retrieving & executing discovered orders and enrolling in the Gouda RFQ program.

## 1. Defining a Filler Execution Strategy

To execute a discovered order, a filler needs to call one of the `execute` methods ([source](https://github.com/Uniswap/gouda/blob/de36900fa074784bda215b902d4854bdffab09ba/src/reactors/BaseReactor.sol#L31)) of the [Dutch Limit Order Reactor](https://etherscan.io/address/0x8Cc1AaF08Ce7F48E4104196753bB1daA80E3530f), providing it with the orders to execute along with the address of the executor contract that defines their fill strategy.

The simplest fill strategy is called `Direct Taker`, where the trade is executed directly against tokens held in the fillers address. To use this strategy, we’ve provided a short cut so fillers do not need to deploy an executor contract. They can simply call `execute` with filler address `address(1)` to fill against themselves (see [source](https://github.com/Uniswap/gouda/blob/de36900fa074784bda215b902d4854bdffab09ba/src/reactors/BaseReactor.sol#L73)):

```solidity
// Execute direct taker order
DutchLimitOrderReactor.execute(order, address(1)); 
```

More sophisticated fillers can implement arbitrarily complex strategies by deploying their own Executor contracts. This contract should implement the [IReactorCallback](https://github.com/Uniswap/gouda/blob/main/src/interfaces/IReactorCallback.sol) interface, which takes in an order with input tokens and returns the allotted number of output tokens to the caller. To use an executor contract, fillers simply specify it’s address when calling `execute`:

```solidity
// Execute custom fill strategy
address executor = /* Address of deployed executor contract */ ;
bytes fillData = /* Call data to be sent to your executor contract */; 
DutchLimitOrderReactor.execute(order, executor, fillData); 
```

For convenience, we’ve provided an [example Executor Contract](https://github.com/Uniswap/gouda/blob/main/src/sample-executors/UniswapV3Executor.sol) which demonstrates how a filler could implement a strategy that executes a Gouda order against a Uniswap V3 pool.

## 2. Retrieve & Execute Signed Orders

All signed orders created through the Uniswap UI will be available via the [Gouda Orders Endpoint](https://***REMOVED***.execute-api.us-east-2.amazonaws.com/prod/api-docs). It’s up to the individual filler to architect their own systems for finding and executing orders profitable orders, but the basic flow is as follows: 

1. Call `GET` on the `prod/dutch-auction/orders` of the Gouda Orders Endpoint (see [docs](https://***REMOVED***.execute-api.us-east-2.amazonaws.com/prod/api-docs) for additional query params) to retrieve open signed orders
2. Decode returned orders using the [Gouda SDK](https://github.com/Uniswap/gouda-sdk/#parsing-orders)
3. Determine which orders you would like to execute
4. Send a new transaction to the [execute](https://github.com/Uniswap/gouda/blob/a2025e3306312fc284a29daebdcabb88b50037c2/src/reactors/BaseReactor.sol#L29) or [executeBatch](https://github.com/Uniswap/gouda/blob/a2025e3306312fc284a29daebdcabb88b50037c2/src/reactors/BaseReactor.sol#L37) methods of the [Dutch Limit Order Reactor](https://github.com/Uniswap/gouda/blob/main/src/reactors/DutchLimitOrderReactor.sol) specifying the signed orders you’d like to fill and the address of your executor contract

If the order is valid, it will be competing against other fillers attempts to execute it in a gas auction. For this reason, we recommend submitting these transactions through a service like [Flashbots Protect](https://docs.flashbots.net/flashbots-protect/overview).

## 3. Enroll in Gouda RFQ

The Gouda RFQ system provides selected Fillers the opportunity to provide quotes to Uniswaps users in exchange for a few blocks of exclusive rights to fill Gouda orders.

In this system, fillers will stand up a quote server that adheres to the Gouda RFQ API Contract (below) and responds to requests with quotes. The RFQ participant who submits the best quote for a given order will receive exclusive rights to fill it using their Executor for the first few blocks of the auction. 

### RFQ API Contract

To successfully receive and respond to Gouda RFQ Quotes, Fillers should have a publicly accessible endpoint that receives quote requests and responds with quotes by implementing the following:

```jsx
method: POST
content-type: application/json
data: {
    requestId: "string uuid - a unique identifier for this quote request", 
    chainId: "number - the chainId that the order is meant to be executed on",
    offerer: "string address - The swapper’s EOA address that will sign the order",
    tokenIn: "string address - The ERC20 token that the swapper will provide",
    amountIn: "string number - The amount of `tokenIn` that the swapper will provide",
    tokenOut: "string address - The ERC20 token that the swapper will receive"
}
```

Response:

```jsx
{
	{ ...All fields from the request echoed...},
	amountOut: "string number - The amount of tokenOut that you will provide in return for `amountIn` units of tokenIn", 
	filler: "string address - The executor address that you would like to have last-look exclusivity for this order"
}
```

There is a latency requirement on responses from registered endpoints. Currently set to 0.5s, but will likely tweak during testing.

Once this server is stood up and available, message your Uniswap Labs contact with its available URL to onboard it to Gouda RFQ and start receiving quote requests. 

### (Optional) Signed Order Webhook Notifications

Signed open orders can always be fetched via the Gouda API, but to provide improved latency there is the option to register for webhook notifications. Fillers can register an endpoint with a filter, and receive notifications for every newly posted order that matches the filter. 

**Filter**

Orders can be filtered by various fields, but most relevant here is `filler`. When registering your webhook notification endpoint, you must provide the `filler` address that you plan to use to execute orders and to receive the last-look exclusivity period.

**Notification**

Order notifications will be sent to the registered endpoint as http requests as follows:

```jsx
method: POST
content-type: application/json
data: {
     orderHash: "the hash identifier for the order", 
    createdAt: "timestamp at which the order was posted",
    signature: "the swapper signature to include with order execution",
    offerer: "the swapper address",
    orderStatus: "current order status (always should be `active` upon receiving notification)",
    encodedOrder: "The abi-encoded order to include with order execution. This can be decoded using the Gouda-SDK (https://github.com/uniswap/gouda-sdk) to verify order fields and signature"
}
```

# Helpful Links

| Name  | Description | Link |
| --- | --- | --- |
| Gouda Orders Endpoint | Publicly available endpoint for querying open Gouda Orders | https://nwktw6mvek.execute-api.us-east-2.amazonaws.com/prod/api-docs  |
| Order Creation UI | A test UI that allows you to create, sign and broadcast Gouda orders. |https://interface-gouda.vercel.app/ |
| Permit2 | Uniswap’s permit protocol used by swappers to sign orders.  | https://github.com/Uniswap/permit2 |



# Deployment Addresses

| Contract | Address | Source |
| --- | --- | --- |
| Dutch Limit Order Reactor | [https://etherscan.io/address/0x81f570f48BE8d3D358404f257b5bDC4A88eefA50](https://etherscan.io/address/0x81f570f48BE8d3D358404f257b5bDC4A88eefA50) | https://github.com/Uniswap/gouda/blob/main/src/reactors/DutchLimitOrderReactor.sol |
| Permit2 | https://etherscan.io/address/0x000000000022D473030F116dDEE9F6B43aC78BA3 | https://github.com/Uniswap/permit2  |
