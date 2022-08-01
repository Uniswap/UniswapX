// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    TokenAmount,
    OrderInfo,
    Signature
} from "../../interfaces/ReactorStructs.sol";

struct DutchOutput {
    address token;
    uint256 startAmount;
    uint256 endAmount;
    address recipient;
}

struct DutchLimitOrder {
    OrderInfo info;
    uint256 startTime;
    uint256 endTime;
    TokenAmount input;
    DutchOutput[] outputs;
}

struct DutchLimitOrderExecution {
    DutchLimitOrder order;
    Signature sig;
    address fillContract;
    bytes fillData;
}
