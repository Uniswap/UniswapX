// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {BaseReactor} from "../BaseReactor.sol";
import {LimitOrder} from "./LimitOrderStructs.sol";
import {ResolvedOrder, OrderInfo, InputToken} from "../../lib/ReactorStructs.sol";

/// @notice Reactor for simple limit orders
contract LimitOrderReactor is BaseReactor {
    constructor(address _permitPost) BaseReactor(_permitPost) {}

    /// @notice Resolve a LimitOrder into a generic order
    /// @dev limit order inputs and outputs are directly specified
    function resolve(bytes memory order) public pure override returns (ResolvedOrder memory resolvedOrder) {
        LimitOrder memory limitOrder = abi.decode(order, (LimitOrder));
        resolvedOrder = ResolvedOrder(limitOrder.info, limitOrder.input, limitOrder.outputs);
    }
}
