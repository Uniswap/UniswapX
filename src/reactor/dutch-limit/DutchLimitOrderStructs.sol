// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    TokenAmount,
    Output,
    OrderInfo,
    Signature
} from "../../interfaces/ReactorStructs.sol";

struct DutchLimitOrder {
    OrderInfo info;
    uint256 startTime;
    uint256 endTime;
    TokenAmount input;
    Output[] outputs;
}

struct DutchLimitOrderExecution {
    DutchLimitOrder order;
    Signature sig;
    address fillContract;
    bytes fillData;
}
