// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {Signature} from "permitpost/interfaces/IPermitPost.sol";
import {InputToken, OutputToken, OrderInfo} from "../../base/ReactorStructs.sol";

struct LimitOrder {
    OrderInfo info;
    InputToken input;
    OutputToken[] outputs;
}
