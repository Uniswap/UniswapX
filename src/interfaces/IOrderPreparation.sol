// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {OrderInfo, ResolvedOrder} from "../base/ReactorStructs.sol";

/// @notice Callback to validate an order
interface IOrderPreparation {
    /// @notice Called by the reactor for custom validation of an order. Will revert with `ValidationFailed()` if
    /// custom validation fails. If this function doesn't revert, then that means the order is valid.
    /// @param resolvedOrder The resolved order to fill
    /// @param filler The filler of the order
    /// @return updatedOrder The prepared order
    function prepare(ResolvedOrder calldata resolvedOrder, address filler)
        external
        view
        returns (ResolvedOrder memory updatedOrder);
}
