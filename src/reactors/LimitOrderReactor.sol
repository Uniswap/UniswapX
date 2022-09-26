// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {BaseReactor} from "./BaseReactor.sol";
import {ResolvedOrder, OrderInfo, InputToken, OutputToken} from "../base/ReactorStructs.sol";

/// @notice Reactor for simple limit orders
contract LimitOrderReactor is BaseReactor {
    constructor(address _permitPost) BaseReactor(_permitPost) {}

    /// @notice Resolve the encoded order into a generic order
    /// @dev limit order inputs and outputs are directly specified
    function resolve(bytes memory order) internal pure override returns (ResolvedOrder memory resolvedOrder) {
        resolvedOrder = abi.decode(order, (ResolvedOrder));
    }
}
