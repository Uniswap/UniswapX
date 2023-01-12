// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {XOrderInfo, ResolvedXOrder} from "../base/XReactorStructs.sol";

/// @notice Callback to validate an order
interface IXValidationCallback {
    /// @notice Called by the reactor for custom validation of an order
    /// @param filler The filler of the order
    /// @param resolvedOrder The resolved order to fill
    /// @return true if valid, else false
    function validate(address filler, ResolvedXOrder calldata resolvedOrder) external view returns (bool);
}
