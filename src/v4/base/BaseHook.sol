// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPreExecutionHook} from "../interfaces/IHook.sol";
import {ResolvedOrder} from "./ReactorStructs.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {Permit2Lib} from "../lib/Permit2Lib.sol";
import {IAuctionResolver} from "../interfaces/IAuctionResolver.sol";

/// @notice Base hook contract that enforces token transfer logic
/// @dev All pre-execution hooks MUST inherit from this contract to ensure token transfers happen
abstract contract BasePreExecutionHook is IPreExecutionHook {
    using Permit2Lib for ResolvedOrder;

    /// @notice Permit2 instance for signature verification and token transfers
    IPermit2 public immutable permit2;

    constructor(IPermit2 _permit2) {
        permit2 = _permit2;
    }

    /// @inheritdoc IPreExecutionHook
    function preExecutionHook(address filler, ResolvedOrder calldata resolvedOrder) external override {
        _beforeTokenTransfer(filler, resolvedOrder);
        _transferInputTokens(resolvedOrder, filler);
        _afterTokenTransfer(filler, resolvedOrder);
    }

    /// @notice Hook for custom logic before token transfer
    /// @param filler The filler of the order
    /// @param resolvedOrder The resolved order to fill
    /// @dev Override this to add custom validation or state changes before transfer
    function _beforeTokenTransfer(address filler, ResolvedOrder calldata resolvedOrder) internal virtual {
        // Default implementation: no-op
        // Derived contracts can override to add custom logic
    }

    /// @notice Hook for custom logic after token transfer
    /// @param filler The filler of the order
    /// @param resolvedOrder The resolved order to fill
    /// @dev Override this to add custom state changes after transfer
    function _afterTokenTransfer(address filler, ResolvedOrder calldata resolvedOrder) internal virtual {
        // Default implementation: no-op
        // Derived contracts can override to add custom logic
    }

    /// @notice Transfer input tokens from swapper to filler using permitWitnessTransferFrom
    /// @dev This function is final and cannot be overridden to ensure transfers always happen
    function _transferInputTokens(ResolvedOrder calldata order, address to) private {
        // Get the order type from the resolver for permit2 witness
        string memory orderType = IAuctionResolver(order.auctionResolver).getPermit2OrderType();

        // Execute the token transfer via Permit2
        permit2.permitWitnessTransferFrom(
            order.toPermit(), order.transferDetails(to), order.info.swapper, order.hash, orderType, order.sig
        );
    }
}
