// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IPreExecutionHook} from "../interfaces/IHook.sol";
import {ResolvedOrder} from "../base/ReactorStructs.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {IReactor} from "../interfaces/IReactor.sol";
import {TokenTransferLib} from "../lib/TokenTransferLib.sol";

/// @notice Canonical token transfer hook contract that uses permit2's Signature transfer
contract TokenTransferHook is IPreExecutionHook {
    /// @notice Permit2 instance for signature verification and token transfers
    IPermit2 public immutable PERMIT2;

    /// @notice v4 Reactor
    IReactor public immutable REACTOR;

    modifier onlyReactor() {
        require(msg.sender == address(REACTOR));
        _;
    }

    constructor(IPermit2 _permit2, IReactor _reactor) {
        PERMIT2 = _permit2;
        REACTOR = _reactor;
    }

    /// @inheritdoc IPreExecutionHook
    function preExecutionHook(address filler, ResolvedOrder calldata resolvedOrder) external override onlyReactor {
        TokenTransferLib.transferInputTokens(PERMIT2, resolvedOrder, filler);
    }
}
