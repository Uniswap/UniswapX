// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {DutchOrderReactor, ResolvedOrder, SignedOrder} from "../../../src/reactors/DutchOrderReactor.sol";

contract MockDutchOrderReactor is DutchOrderReactor {
    constructor(address _permit2, address _protocolFeeOwner) DutchOrderReactor(_permit2, _protocolFeeOwner) {}

    function resolveOrder(SignedOrder calldata order) external view returns (ResolvedOrder memory resolvedOrder) {
        return resolve(order);
    }

    function resolve(SignedOrder calldata order) internal view override returns (ResolvedOrder memory resolvedOrder) {
        return DutchOrderReactor.resolve(order);
    }
}
