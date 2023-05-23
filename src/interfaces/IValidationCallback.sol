// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {OrderInfo, ResolvedOrder} from "../base/ReactorStructs.sol";

/// @notice Callback to validate an order
interface IValidationCallback {
    /// @notice Called by the reactor for custom validation of an order. Will revert if validation fails
    /// @param filler The filler of the order
    /// @param resolvedOrder The resolved order to fill
    function validate(address filler, ResolvedOrder calldata resolvedOrder) external view;
}
