// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {ResolvedOrder} from "../base/ReactorStructs.sol";
import {Permit2Lib} from "./Permit2Lib.sol";
import {IAuctionResolver} from "../interfaces/IAuctionResolver.sol";

/// @notice Library for transferring input tokens using Permit2
library TokenTransferLib {
    using Permit2Lib for ResolvedOrder;

    /// @notice Transfer input tokens from swapper to filler using permitWitnessTransferFrom
    /// @param permit2 The Permit2 contract instance
    /// @param order The resolved order containing transfer details
    /// @param to The recipient address (typically the filler)
    function signatureTransferInputTokens(IPermit2 permit2, ResolvedOrder calldata order, address to) internal {
        // Get the order type from the resolver for permit2 witness
        string memory orderType = IAuctionResolver(order.auctionResolver).getPermit2OrderType();

        // Execute the token transfer via Permit2
        permit2.permitWitnessTransferFrom(
            order.toPermit(), order.transferDetails(to), order.info.swapper, order.hash, orderType, order.sig
        );
    }

    /// @notice Set allowance for tokens using permit signature
    /// @dev Hook should call this first if a permit signature is provided
    /// @param permit2 The Permit2 contract instance
    /// @param owner The token owner granting the allowance
    /// @param permitSingle The permit details including spender, amount, expiration
    /// @param signature The signature over the permit data
    function setAllowance(
        IPermit2 permit2,
        address owner,
        IAllowanceTransfer.PermitSingle calldata permitSingle,
        bytes calldata signature
    ) internal {
        permit2.permit(owner, permitSingle, signature);
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
