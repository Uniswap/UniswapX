// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

struct Signature {
    uint8 v;
    bytes32 r;
    bytes32 s;
}

struct TokenAmount {
    address token;
    uint256 amount;
}

struct OrderInfo {
    address reactor;
    address offerer;
    address validationContract;
    bytes validationData;
    uint256 counter;
    uint256 deadline;
}

struct Order {
    OrderInfo info;
    bytes data;
}

struct OrderExecution {
    Order order;
    Signature sig;
    address fillContract;
    bytes fillData;
}

// internal structs
struct Output {
    address token;
    uint256 amount;
    address recipient;
}

struct ResolvedOrder {
    TokenAmount input;
    TokenAmount[] outputs;
}
