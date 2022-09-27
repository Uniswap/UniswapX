// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {DutchLimitOrderReactor, ResolvedOrder} from "../../../src/reactors/DutchLimitOrderReactor.sol";

contract MockDutchLimitOrderReactor is DutchLimitOrderReactor {
    constructor(address permitPost) DutchLimitOrderReactor(permitPost) {}

    function resolveOrder(bytes memory order) external view returns (ResolvedOrder memory resolvedOrder) {
        return resolve(order);
    }

    function resolve(bytes memory order) internal view override returns (ResolvedOrder memory resolvedOrder) {
        return DutchLimitOrderReactor.resolve(order);
    }
}
