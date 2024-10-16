// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ResolvedOrder} from "../../../src/base/ReactorStructs.sol";
import {ExclusivityLib} from "../../../src/lib/ExclusivityLib.sol";

contract MockExclusivityLib {
    function handleExclusiveOverrideTimestamp(
        ResolvedOrder memory order,
        address exclusive,
        uint256 exclusivityEnd,
        uint256 exclusivityOverrideBps
    ) external view returns (ResolvedOrder memory) {
        ExclusivityLib.handleExclusiveOverrideTimestamp(order, exclusive, exclusivityEnd, exclusivityOverrideBps);
        return order;
    }

    function handleExclusiveOverrideBlock(
        ResolvedOrder memory order,
        address exclusive,
        uint256 exclusivityEnd,
        uint256 exclusivityOverrideBps,
        uint256 blockNumberish
    ) external view returns (ResolvedOrder memory) {
        ExclusivityLib.handleExclusiveOverrideBlock(
            order, exclusive, exclusivityEnd, exclusivityOverrideBps, blockNumberish
        );
        return order;
    }

    function hasFillingRights(address exclusive, uint256 exclusivityEnd, uint256 currentPosition)
        external
        view
        returns (bool pass)
    {
        return ExclusivityLib.hasFillingRights(exclusive, exclusivityEnd, currentPosition);
    }
}
