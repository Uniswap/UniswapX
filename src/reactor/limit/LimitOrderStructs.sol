// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    TokenAmount, Output, OrderInfo
} from "../../interfaces/ReactorStructs.sol";

struct LimitOrderData {
    TokenAmount input;
    Output[] outputs;
}
