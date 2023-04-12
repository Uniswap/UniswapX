// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {DutchLimitOrderReactor, ResolvedOrder, SignedOrder} from "../../../src/reactors/DutchLimitOrderReactor.sol";

contract MockDutchLimitOrderReactor is DutchLimitOrderReactor {
    constructor(address _permit2, address _protocolFeeOwner) DutchLimitOrderReactor(_permit2, _protocolFeeOwner) {}

    function resolveOrder(SignedOrder calldata order) external view returns (ResolvedOrder memory resolvedOrder) {
        return resolve(order);
    }

    function resolve(SignedOrder calldata order) internal view override returns (ResolvedOrder memory resolvedOrder) {
        return DutchLimitOrderReactor.resolve(order);
    }
}
