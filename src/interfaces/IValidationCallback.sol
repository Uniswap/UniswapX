// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {OrderInfo} from "./ReactorStructs.sol";

/// @notice Callback to validate an order
interface IValidationCallback {
    /// @notice Called by the reactor for custom validation of an order
    /// @param order The order to validate
    /// @return true if valid, else false
    function validate(OrderInfo memory order) external view returns (bool);
}
