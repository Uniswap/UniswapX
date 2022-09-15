// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Signature} from "permitpost/interfaces/IPermitPost.sol";
import {OrderInfo} from "../../lib/ReactorStructs.sol";

struct DutchOutput {
    address token;
    uint256 startAmount;
    uint256 endAmount;
    address recipient;
}

struct DutchInput {
    address token;
    uint256 startAmount;
    uint256 endAmount;
}

struct DutchLimitOrder {
    OrderInfo info;
    uint256 startTime;
    uint256 endTime;
    DutchInput input;
    DutchOutput[] outputs;
}
