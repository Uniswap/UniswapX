// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {Signature} from "permitpost/interfaces/IPermitPost.sol";
import {InputToken, OrderInfo} from "../../lib/ReactorStructs.sol";

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
    InputToken input;
    DutchOutput[] outputs;
}
