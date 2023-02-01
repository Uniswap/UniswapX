# What is Gouda?

[Gouda](https://github.com/uniswap/gouda) is an off-chain order execution protocol meant to generalize token swaps across liquidity sources and provide price improvement for users. “Offerers” generate signed messages specifying the terms of their trade, in the form of a linear-decay Dutch order. 
<p align="center">
<img width="575" alt="image" src="https://user-images.githubusercontent.com/8218221/216129758-df0ae2a3-05a7-44a2-bd79-0c7b1c10b8cb.png">
</p>
“Fillers” read these orders and execute them, taking input assets from the offerer and fulfilling output assets. Fillers are entitled to keep any spread or profits they are able to generate by fulfilling orders. 

## Gouda Order Flow:

To Offerers on the Uniswap front end, Gouda orders look just like any other Uniswap order but behind the scenes they have a completely different flow. 
<p align="center">
<img width="787" alt="image" src="https://user-images.githubusercontent.com/8218221/216130260-122b7389-bb8a-404e-a062-b626f254fafd.png">
</p>

1. A Gouda order starts with an offerer on a Uniswap front end requesting a quote by entering two tokens and an input or output amount
2. That request is sent to Gouda’s private network of RFQ Fillers who provide quotes for the proposed order. The best quote provided, is returned to offerer on the Uniswap front end
3. The quote is transformed into a decaying Dutch Order by the Uniswap front end. It will decay over a preset number of blocks from the winning RFQ quote to Uniswap router price. If the offerer wants the order they will sign it. 
4. The signed order is first sent to the winner of the RFQ. They will have a set a number of blocks to fill at their winning bid price
5. If the RFQ winner fades, the signed order is then broadcast publicly. Any filler is then able to compete to fill the order at the given price in its decay curve. 

## Gouda Protocol Architecture:

The Gouda Protocol uses two types of contract, **Order Reactors** and **Order Executors,** to allow a network of Fillers to execute signed orders created through the Uniswap front end and signed via [Permit2](https://github.com/Uniswap/permit2): 

<p align="center">
<img width="771" alt="image" src="https://user-images.githubusercontent.com/8218221/216130577-e7f9263b-b5a7-463a-b082-6b8bc4d7d41c.png">
</p>
  
**[Order Reactors](https://github.com/Uniswap/gouda/blob/main/src/interfaces/IReactor.sol)** are contracts that take in a specific type of order objects (like Dutch Orders), validate them, convert them to generic orders, and then execute them against a Filler’s Executor contract. 

The **[Dutch Limit Order Reactor](https://github.com/Uniswap/gouda/blob/main/src/reactors/DutchLimitOrderReactor.sol)** is Uniswaps Labs currently deployed reactor that allows execution of decaying Dutch Limit Orders created through Uniswaps interface. 

**[Order Executors](https://github.com/Uniswap/gouda/blob/main/src/interfaces/IReactorCallback.sol)** (called **[ReactorCallback](https://github.com/Uniswap/gouda/blob/main/src/interfaces/IReactorCallback.sol))** are contracts created by fillers that defines their individual execution strategy which will be called by the reactor, in order to execute requested orders (you can find sample executor contracts [here](https://github.com/Uniswap/gouda/tree/main/src/sample-executors))

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

# Helpful Links

| Name  | Description | Link |
| --- | --- | --- |
| Gouda Orders Endpoint | Publicly available endpoint for querying open Gouda Orders | https://6q5qkya37k.execute-api.us-east-2.amazonaws.com/prod |
| Gouda Orders Endpoint Docs | Docs showing the available fields to query for the Gouda Orders Endpoint. | https://6q5qkya37k.execute-api.us-east-2.amazonaws.com/prod/api-docs |
| Permit2 | Uniswap’s permit protocol used by offerers to sign orders.  | https://github.com/Uniswap/permit2 |

# Deployment Addresses

| Contract | Address | Source |
| --- | --- | --- |
| Dutch Limit Order Reactor | https://etherscan.io/address/0x8Cc1AaF08Ce7F48E4104196753bB1daA80E3530f | https://github.com/Uniswap/gouda/blob/main/src/reactors/DutchLimitOrderReactor.sol |
| Permit2 | https://etherscan.io/address/0x000000000022D473030F116dDEE9F6B43aC78BA3 | https://github.com/Uniswap/permit2  |
