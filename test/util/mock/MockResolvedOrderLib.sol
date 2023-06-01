// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {OrderInfo, ResolvedOrder} from "../../../src/base/ReactorStructs.sol";
import {ResolvedOrderLib} from "../../../src/lib/ResolvedOrderLib.sol";

contract MockResolvedOrderLib {
    using ResolvedOrderLib for ResolvedOrder;

    function validate(ResolvedOrder memory resolvedOrder, address filler) external view {
        resolvedOrder.validate(filler);
    }
}
