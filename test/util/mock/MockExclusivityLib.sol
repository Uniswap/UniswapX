// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ResolvedOrder} from "../../../src/base/ReactorStructs.sol";
import {ExclusivityLib} from "../../../src/lib/ExclusivityLib.sol";

contract MockExclusivityLib {
    function handleExclusiveOverride(
        ResolvedOrder memory order,
        address exclusive,
        uint256 exclusivityEndTime,
        uint256 exclusivityOverrideBps
    ) external view returns (ResolvedOrder memory) {
        ExclusivityLib.handleExclusiveOverride(order, exclusive, exclusivityEndTime, exclusivityOverrideBps);
        return order;
    }

    function hasFillingRights(address exclusive, uint256 exclusivityEndTime) external view returns (bool pass) {
        return ExclusivityLib.hasFillingRights(exclusive, exclusivityEndTime);
    }
}
