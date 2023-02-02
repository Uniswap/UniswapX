# Integrating as a Filler

There are three components to integrating as a filler: creating an executor contract, retrieving & executing discovered orders and enrolling in the Gouda RFQ program.

## 1. Create an Executor Contract

To actually execute discovered Gouda orders each filler will need to create and deploy their own Executor contracts. These contracts define a filler’s custom fill strategy. The contract should implement the [IReactorCallback](https://github.com/Uniswap/gouda/blob/main/src/interfaces/IReactorCallback.sol) interface, which takes in an order with input tokens and returns the allotted number of output tokens to the caller. 

The most basic implementation of an executor simply accepts the input tokens from an order and returns the sender the requested number of output tokens ([source](https://github.com/Uniswap/gouda/blob/main/src/sample-executors/DirectTakerExecutor.sol) below), but can be designed with arbitrarily complex execution strategies:

```solidity
contract DirectTakerExecutor is IReactorCallback, Owned {
    using SafeTransferLib for ERC20;

    constructor(address _owner) Owned(_owner) {}

    function reactorCallback(ResolvedOrder[] calldata resolvedOrders, address taker, bytes calldata) external {
        // Only handle 1 resolved order
        require(resolvedOrders.length == 1, "resolvedOrders.length != 1");

        uint256 totalOutputAmount;
        // transfer output tokens from taker to this
        for (uint256 i = 0; i < resolvedOrders[0].outputs.length; i++) {
            OutputToken memory output = resolvedOrders[0].outputs[i];
            ERC20(output.token).safeTransferFrom(taker, address(this), output.amount);
            totalOutputAmount += output.amount;
        }
        // Assumed that all outputs are of the same token
        ERC20(resolvedOrders[0].outputs[0].token).approve(msg.sender, totalOutputAmount);
        // transfer input tokens from this to taker
        ERC20(resolvedOrders[0].input.token).safeTransfer(taker, resolvedOrders[0].input.amount);
    }
}
```

When a filler goes to execute a profitable order, they will submit a transaction containing the order and a pointer to their deployed Executor to execute the order.  

## 2. Retrieve & Execute Signed Orders

All signed orders created through the Uniswap UI will be available via the [Gouda Orders Endpoint](https://6q5qkya37k.execute-api.us-east-2.amazonaws.com/prod/api-docs). It’s up to the individual filler to architect their own systems for finding and executing orders profitable orders, but the basic flow is as follows: 

1. Call `GET` on the `prod/dutch-auction/orders` of the Gouda Orders Endpoint (see [docs](https://6q5qkya37k.execute-api.us-east-2.amazonaws.com/prod/api-docs) for additional query params) to retrieve open signed orders
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
    offerer: "string address - The offerer’s EOA address that will sign the order"
    tokenIn: "string address - The ERC20 token that the offerer will provide",
    amountIn: "string number - The amount of `tokenIn` that the offerer will provide",
    tokenOut: "string address - The ERC20 token that the offerer will receive"
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
    signature: "the offerer signature to include with order execution",
    offerer: "the offerer address",
    orderStatus: "current order status (always should be `active` upon receiving notification)",
    encodedOrder: "The abi-encoded order to include with order execution. This can be decoded using the Gouda-SDK (https://github.com/uniswap/gouda-sdk) to verify order fields and signature"
}
```

# Helpful Links

| Name  | Description | Link |
| --- | --- | --- |
| Gouda Orders Endpoint | Publicly available endpoint for querying open Gouda Orders | [https://6q5qkya37k.execute-api.us-east-2.amazonaws.com/prod](https://6q5qkya37k.execute-api.us-east-2.amazonaws.com/prod/api-docs) |
| Order Creation UI | A test UI that allows you to create, sign and broadcast Gouda orders. | https://gouda-ui-zachyang-uniswaporg.vercel.app/#/swap |
| Permit2 | Uniswap’s permit protocol used by offerers to sign orders.  | https://github.com/Uniswap/permit2 |

# Deployment Addresses

| Contract | Address | Source |
| --- | --- | --- |
| Dutch Limit Order Reactor | https://etherscan.io/address/0x8Cc1AaF08Ce7F48E4104196753bB1daA80E3530f | https://github.com/Uniswap/gouda/blob/main/src/reactors/DutchLimitOrderReactor.sol |
| Permit2 | https://etherscan.io/address/0x000000000022D473030F116dDEE9F6B43aC78BA3 | https://github.com/Uniswap/permit2  |
