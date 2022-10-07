// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {BaseReactor} from "./BaseReactor.sol";
import {SignedOrder, ResolvedOrder, OrderInfo, InputToken, OutputToken} from "../base/ReactorStructs.sol";

/// @dev External struct used to specify simple limit orders
struct LimitOrder {
    // generic order information
    OrderInfo info;
    // The tokens that the offerer will provide when settling the order
    InputToken input;
    // The tokens that must be received to satisfy the order
    OutputToken[] outputs;
}

/// @notice Reactor for simple limit orders
contract LimitOrderReactor is BaseReactor {
    constructor(address _permitPost) BaseReactor(_permitPost) {}

    /// @notice Resolve the encoded order into a generic order
    /// @dev limit order inputs and outputs are directly specified
    function resolve(SignedOrder memory signedOrder)
        internal
        pure
        override
        returns (ResolvedOrder memory resolvedOrder)
    {
        LimitOrder memory limitOrder = abi.decode(signedOrder.order, (LimitOrder));
        resolvedOrder = ResolvedOrder({
            info: limitOrder.info,
            input: limitOrder.input,
            outputs: limitOrder.outputs,
            sig: signedOrder.sig,
            hash: keccak256(signedOrder.order)
        });
    }
}
