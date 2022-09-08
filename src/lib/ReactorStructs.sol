// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Signature} from "permitpost/interfaces/IPermitPost.sol";

struct TokenAmount {
    address token;
    uint256 amount;
}

struct OrderInfo {
    address reactor;
    uint256 nonce;
    uint256 deadline;
}

struct Output {
    address token;
    uint256 amount;
    address recipient;
}

struct ResolvedOrder {
    OrderInfo info;
    TokenAmount input;
    Output[] outputs;
}

struct OrderStatus {
    bool isCancelled;
    // TODO: use numerator/denominator for partial fills
    bool isFilled;
}

struct SignedOrder {
    bytes order;
    Signature sig;
}
