// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ResolvedOrder} from "../../../src/base/ReactorStructs.sol";
import {ExclusivityOverrideLib} from "../../../src/lib/ExclusivityOverrideLib.sol";

contract MockExclusivityOverrideLib {
    function handleOverride(
        ResolvedOrder memory order,
        address exclusive,
        uint256 exclusivityEndTime,
        uint256 exclusivityOverrideBps
    ) external view returns (ResolvedOrder memory) {
        ExclusivityOverrideLib.handleOverride(order, exclusive, exclusivityEndTime, exclusivityOverrideBps);
        return order;
    }

    function checkExclusivity(address exclusive, uint256 exclusivityEndTime) external view returns (bool pass) {
        return ExclusivityOverrideLib.checkExclusivity(exclusive, exclusivityEndTime);
    }
}
