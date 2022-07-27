// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {LimitOrderData} from "./LimitOrderStructs.sol";
import {
    Order,
    ResolvedOrder,
    TokenAmount
} from "../../interfaces/ReactorStructs.sol";
import {BaseReactor} from "../BaseReactor.sol";

/// @notice Reactor for simple limit orders
contract LimitOrderReactor is BaseReactor {
    function _resolve(Order calldata order)
        internal
        pure
        override
        returns (ResolvedOrder memory)
    {
        LimitOrderData memory data = abi.decode(order.data, (LimitOrderData));
        return ResolvedOrder(data.input, data.outputs);
    }
}
