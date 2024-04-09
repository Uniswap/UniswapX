// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {DutchOrderReactor, ResolvedOrder, SignedOrder} from "../../../src/reactors/DutchOrderReactor.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";

contract MockDutchOrderReactor is DutchOrderReactor {
    constructor(IPermit2 _permit2, address _protocolFeeOwner) DutchOrderReactor(_permit2, _protocolFeeOwner) {}

    function resolveOrder(SignedOrder calldata order) external view returns (ResolvedOrder memory resolvedOrder) {
        return _resolve(order);
    }

    function _resolve(SignedOrder calldata order) internal view override returns (ResolvedOrder memory resolvedOrder) {
        return DutchOrderReactor._resolve(order);
    }
}
