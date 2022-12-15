// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {OrderInfo, ResolvedOrder} from "../base/ReactorStructs.sol";

/// @notice Callback to validate an order
interface IValidationCallback {
    /// @notice Called by the reactor for custom validation of an order
    /// @param filler The filler of the order
    /// @param resolvedOrder The resolved order to fill
    /// @return true if valid, else false
    function validate(address filler, ResolvedOrder calldata resolvedOrder) external view returns (bool);
}
