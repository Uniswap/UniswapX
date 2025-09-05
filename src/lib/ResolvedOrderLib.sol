// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ResolvedOrder} from "../base/ReactorStructs.sol";

/// @notice Library for handling validation of resolved orders
library ResolvedOrderLib {
    /// @notice thrown when the order targets a different reactor
    error InvalidReactor();

    /// @notice Validates a resolved order, reverting if invalid
    /// @param filler The filler of the order
    function validate(ResolvedOrder memory resolvedOrder, address filler) internal view {
        if (address(this) != address(resolvedOrder.info.reactor)) {
            revert InvalidReactor();
        }

        if (address(resolvedOrder.info.additionalValidationContract) != address(0)) {
            resolvedOrder.info.additionalValidationContract.validate(filler, resolvedOrder);
        }
    }
}
