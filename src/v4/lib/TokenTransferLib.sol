// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
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
    function transferInputTokens(IPermit2 permit2, ResolvedOrder calldata order, address to) internal {
        // Get the order type from the resolver for permit2 witness
        string memory orderType = IAuctionResolver(order.auctionResolver).getPermit2OrderType();

        // Execute the token transfer via Permit2
        permit2.permitWitnessTransferFrom(
            order.toPermit(), order.transferDetails(to), order.info.swapper, order.hash, orderType, order.sig
        );
    }
}
