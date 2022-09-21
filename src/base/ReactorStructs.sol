// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {Signature} from "permitpost/interfaces/IPermitPost.sol";

struct InputToken {
    address token;
    uint256 amount;
}

struct OrderInfo {
    address reactor;
    address offerer;
    uint256 nonce;
    uint256 deadline;
}

struct OutputToken {
    address token;
    uint256 amount;
    address recipient;
}

struct ResolvedOrder {
    OrderInfo info;
    InputToken input;
    OutputToken[] outputs;
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
