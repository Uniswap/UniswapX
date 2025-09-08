// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {BasePreExecutionHook} from "../base/BaseHook.sol";
import {ResolvedOrderV2} from "../base/ReactorStructs.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";

/// @notice Minimal hook that only performs token transfers with no additional logic
/// @dev This is the canonical hook for standard UniswapX orders
contract TokenTransferHook is BasePreExecutionHook {
    constructor(IPermit2 _permit2) BasePreExecutionHook(_permit2) {}
}
