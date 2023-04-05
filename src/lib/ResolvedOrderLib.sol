// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {ResolvedOrder} from "../base/ReactorStructs.sol";
import {IOrderPreparation} from "../interfaces/IOrderPreparation.sol";

library ResolvedOrderLib {
    error InvalidReactor();
    error DeadlinePassed();

    /// @notice Validates and prepares a resolved order, reverting if invalid
    /// @param filler The filler of the order
    function prepare(ResolvedOrder memory resolvedOrder, address filler)
        internal
        view
        returns (ResolvedOrder memory)
    {
        if (address(this) != resolvedOrder.info.reactor) {
            revert InvalidReactor();
        }

        if (block.timestamp > resolvedOrder.info.deadline) {
            revert DeadlinePassed();
        }

        if (resolvedOrder.info.preparationContract != address(0)) {
            return IOrderPreparation(resolvedOrder.info.preparationContract).prepare(filler, resolvedOrder);
        }
        return resolvedOrder;
    }
}
