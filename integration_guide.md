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

## 3. Enroll in UniswapX RFQ

The UniswapX RFQ system provides selected Fillers the opportunity to provide quotes to Uniswaps users in exchange for a few blocks of exclusive rights to fill UniswapX orders.

In this system, fillers will stand up a quote server that adheres to the UniswapX RFQ API Contract (below) and responds to requests with quotes. The RFQ participant who submits the best quote for a given order will receive exclusive rights to fill it using their Executor for the first few blocks of the auction. 

### RFQ API Contract

To successfully receive and respond to UniswapX RFQ Quotes, Fillers should have a publicly accessible endpoint that receives quote requests and responds with quotes by implementing the following:

```jsx
method: POST
content-type: application/json
data: {
    requestId: "string uuid - a unique identifier for this quote request", 
    tokenInChainId: "number - the `tokenIn` chainId",
    tokenOutChainId: "number - the `tokenOut` chainId",
    swapper: "string address - The swapper’s EOA address that will sign the order",
    tokenIn: "string address - The ERC20 token that the swapper will provide",
    tokenOut: "string address - The ERC20 token that the swapper will receive",
    amount: "string number - If the trade type is exact input then this is amount of `tokenIn` the user wants to swap otherwise this is amount of tokenOut the user wants to receive",
    type: "number - This is either `EXACT_INPUT` or `EXACT_OUTPUT`"
}
```

Response:

```jsx
{
    chainId: "number - the chainId for the quoted token",
    amountIn: "string number - If the request type is exact input then this field is `amount` from the quote request, otherwise this is the provided quote",
    amountOut: "string number - If the request type is exact output then this field is `amount` from the quote request, otherwise this is the provided quote", 
    filler: "string address - The executor address that you would like to have last-look exclusivity for this order"

    { ...The following fields should be echoed from the quote request...},
    requestId: "string uuid - a unique identifier for this quote request", 
    swapper: "string address - The swapper’s EOA address that will sign the order",
    tokenIn: "string address - The ERC20 token that the swapper will provide",
    tokenOut: "string address - The ERC20 token that the swapper will receive"
}
```

There is a latency requirement on responses from registered endpoints. Currently set to 0.5s, but will likely tweak during testing. If a filler receives a quote request they do not want to respond to they should send back an empty response with status code `204`.

Once this server is stood up and available, message your Uniswap Labs contact with its available URL to onboard it to UniswapX RFQ and start receiving quote requests. 

### (Optional) Signed Order Webhook Notifications

Signed open orders can always be fetched via the UniswapX API, but to provide improved latency there is the option to register for webhook notifications. Fillers can register an endpoint with a filter, and receive notifications for every newly posted order that matches the filter. 

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
    swapper: "the swapper address",
    orderStatus: "current order status (always should be `active` upon receiving notification)",
    encodedOrder: "The abi-encoded order to include with order execution. This can be decoded using the UniswapX-SDK (https://github.com/uniswap/UniswapX-sdk) to verify order fields and signature",
    chainId: "The chain ID that the order originates from and must be settled on",
    filler?: "If this order was quoted by an RFQ participant then this will be their filler address",
    quoteId?: "If this order was quoted by an RFQ participant then this will be the requestId from the quote request"
}
```

# Helpful Links

| Name  | Description | Link |
| --- | --- | --- |
| UniswapX Orders Endpoint | Publicly available endpoint for querying open UniswapX Orders | https://6q5qkya37k.execute-api.us-east-2.amazonaws.com/prod/api-docs  |
| Order Creation UI | A test UI that allows you to create, sign and broadcast UniswapX orders. |https://interface-UniswapX.vercel.app/ |
| Permit2 | Uniswap’s permit protocol used by swappers to sign orders.  | https://github.com/Uniswap/permit2 |



# Deployment Addresses

| Contract | Address | Source |
| --- | --- | --- |
| Dutch Order Reactor | https://etherscan.io/address/0xbd7f9d0239f81c94b728d827a87b9864972661ec | https://github.com/Uniswap/UniswapX/blob/main/src/reactors/DutchOrderReactor.sol |
| Permit2 | https://etherscan.io/address/0x000000000022D473030F116dDEE9F6B43aC78BA3 | https://github.com/Uniswap/permit2  |
