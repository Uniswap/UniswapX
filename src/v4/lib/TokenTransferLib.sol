// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {ResolvedOrder, GENERIC_ORDER_WITNESS_TYPE} from "../base/ReactorStructs.sol";
import {Permit2Lib} from "./Permit2Lib.sol";

/// @notice Library for transferring input tokens using Permit2
library TokenTransferLib {
    using Permit2Lib for ResolvedOrder;

    /// @notice Transfer input tokens from swapper to filler using permitWitnessTransferFrom
    /// @param permit2 The Permit2 contract instance
    /// @param order The resolved order containing transfer details
    /// @param to The recipient address (typically the filler)
    function signatureTransferInputTokens(IPermit2 permit2, ResolvedOrder calldata order, address to) internal {
        // Execute the token transfer via Permit2 with resolver-provided witness
        // order.hash contains the witness hash, witnessTypeString is provided by the resolver
        permit2.permitWitnessTransferFrom(
            order.toPermit(),
            order.transferDetails(to),
            order.info.swapper,
            order.hash,
            order.witnessTypeString,
            order.sig
        );
    }

    /// @notice Transfer input tokens using existing allowance
    /// @dev Assumes allowance has been set (either via setAllowance or previously)
    /// @param permit2 The Permit2 contract instance
    /// @param order The resolved order containing transfer details
    /// @param to The recipient address (typically the filler)
    function allowanceTransferInputTokens(IPermit2 permit2, ResolvedOrder calldata order, address to) internal {
        permit2.transferFrom(order.info.swapper, to, uint160(order.input.amount), address(order.input.token));
    }
}
