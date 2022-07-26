// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {LimitOrderData} from "./LimitOrderStructs.sol";
import {
    Order,
    ResolvedOrder,
    TokenAmount
} from "../../interfaces/ReactorStructs.sol";
import {BaseReactor} from "../BaseReactor.sol";

contract LimitOrderReactor is BaseReactor {
    function resolve(Order calldata order)
        internal
        override
        returns (ResolvedOrder memory)
    {
        LimitOrderData memory data = abi.decode(order.data, (LimitOrderData));
        TokenAmount[] memory outputs = new TokenAmount[](data.outputs.length);
        for (uint i = 0; i < outputs.length; i++) {
            outputs[i] = TokenAmount(outputs[i].token, outputs[i].amount);
        }
        return ResolvedOrder(data.input, outputs);
    }
}
