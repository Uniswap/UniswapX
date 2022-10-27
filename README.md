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
<img width="1087" alt="Untitled" src="https://user-images.githubusercontent.com/8218221/197440654-ead0fe75-2d4c-4f93-a7ff-b995481cf545.png">

# Integration Overview

- **Agents:**
    - **Swappers:** Users who submit signed Orders to exchange one asset for another through the Uniswap UI, for example
    - **Fillers:** Discover signed Orders from swappers, and execute custom strategies to fill them profitably
- **Components:**
    - *[Order Reactors](https://github.com/Uniswap/gouda/blob/main/src/interfaces/IReactor.sol)*:  Contracts that take in a specific type of order objects (like Dutch Orders), validate them, convert them to generic orders, and then execute them against a Filler’s Executor contract
        - *[Dutch Order Reactor](https://github.com/Uniswap/gouda/blob/main/src/reactors/DutchLimitOrderReactor.sol)*: The specific reactor contract that allows the filling of decaying Dutch Limit Orders.
    - *Order Executor (called [ReactorCallback](https://github.com/Uniswap/gouda/blob/main/src/interfaces/IReactorCallback.sol)):* Contract that defines the Filler’s execution strategy. This will be called by the reactor, after orders are validated to execute them.
    - *[Permit2](https://github.com/Uniswap/permit2):* Allows users to approve contracts to move tokens on their behalf using signed messages.
    - *Uniswap Order Pool:* A service that stores orders created by Uniswap Labs products.
- **End to End Dutch Limit Order Flow:**
    1. A *Swapper* goes to an interface like Uniswap and creates and signs a Dutch Order transaction using Permit2.
        1. This order specifies a Token and Amount in, a Token Out, a Minimum and Maximum Amount out and an expiration. 
        2. This order will decay linearly from creation to expiry from the Maximum Tokens Out to the Minimum Tokens Out
    2. The signed order is stored in an Order Pool (see Uniswap's Order Pool API below)
    3. A *Filler*, queries the *Order Pool* for unfilled orders. They compare them against the filling strategy defined in their *Order Executor.* 
    4. If the trade can be profitably executed, they submit that order object and a pointer to their *Order Executor* to the *Dutch Limit Order Reactor*
    5. The *Dutch Limit Order Reactor* validates the order using *Permit Post* then passes control of the input tokens to the *Order Executor* contract to be used execute the fill strategy.   
    6.  The *Dutch Limit Order Reactor* takes the Output Tokens from the filler contract and sends them to the *Swapper*

## Building a Filler Contract

1. Define an executor or filler ([interface](https://github.com/Uniswap/gouda/blob/main/src/interfaces/IReactorCallback.sol)) contract that implements `IReactorCallback`
    1. The `reactorCallback` method takes in a list of orders, which contain input token and amount and output tokens and amount. By the end of the function, the caller should have access to the amount of `outputToken` defined in the list of orders. 
    2. Some basic example `Executors` can be found in this [repo](https://github.com/Uniswap/gouda/tree/main/src/sample-executors)
2. Find profitable, `SignedOrder`'s ([link](https://github.com/Uniswap/gouda/blob/c4b95723fa4b9e30533d50e931591b2a20d91767/src/base/ReactorStructs.sol#L36)) from the `Order API` 
    1. Call the `GET Orders` method from the API to get open orders 
    2. Assess them against your `Executor` to see if they would be profitable to complete
    3. If they are, send them to the `execute` or `executeBatch` methods on the `DutchLimitOrderReactor` along with your `fillContract` (executor) address, and any extra calldata your executor needs to perform the transaction
3. If all goes correctly, the Reactor will validate the orders you sent, call your `reactorCallback` to execute your strategy, pass you the `inputTokens` from the order and retrieve the `outputTokens` from your `executor` contract

## Integrating with the Order Pool API

Orders created by Uniswap Labs products will be stored in a private Order Pool. Fillers can query for open orders in this pool with the following endpoint:  

**API Docs:**  [https://xmj8fkst53.execute-api.us-east-2.amazonaws.com/prod/api-docs](https://xmj8fkst53.execute-api.us-east-2.amazonaws.com/prod/api-docs)

## Useful Integration Links

- Protocol Source: https://github.com/Uniswap/gouda
    - Example executor contracts: [https://github.com/Uniswap/gouda/tree/main/src/sample-executors](https://github.com/Uniswap/gouda/tree/main/src/sample-executors)
- Example end to end filler bot: https://github.com/Uniswap/gouda-bot
- Order API: [https://xmj8fkst53.execute-api.us-east-2.amazonaws.com/prod/dutch-auction/orders](https://xmj8fkst53.execute-api.us-east-2.amazonaws.com/prod/dutch-auction/orders?limit=100)
- Swagger: [https://xmj8fkst53.execute-api.us-east-2.amazonaws.com/prod/api-docs](https://xmj8fkst53.execute-api.us-east-2.amazonaws.com/prod/api-docs)
- Smart Contract Addresses:
    
    
| Contract                  | Address | GH Link                                                                            |
| ---                       | ---     | ---                                                                                |
| Dutch Limit Order Reactor |         | https://github.com/Uniswap/gouda/blob/main/src/reactors/DutchLimitOrderReactor.sol |
| Permit Post               |         | https://github.com/Uniswap/permit2                                                 |

## Disclaimer
This is EXPERIMENTAL, UNAUDITED code. Do not use in production.
