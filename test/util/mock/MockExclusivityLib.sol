// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ResolvedOrder} from "../../../src/base/ReactorStructs.sol";
import {ExclusivityLib} from "../../../src/lib/ExclusivityLib.sol";

contract MockExclusivityLib {
    function handleExclusiveOverride(
        ResolvedOrder memory order,
        address exclusive,
        uint256 exclusivityEnd,
        uint256 exclusivityOverrideBps,
        bool timeBased
    ) external view returns (ResolvedOrder memory) {
        ExclusivityLib.handleExclusiveOverride(order, exclusive, exclusivityEnd, exclusivityOverrideBps, timeBased);
        return order;
    }

    function hasFillingRights(address exclusive, uint256 exclusivityEnd, bool timeBased) external view returns (bool pass) {
        return ExclusivityLib.hasFillingRights(exclusive, exclusivityEnd, timeBased);
    }
}
