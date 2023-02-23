// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {IOrderSettlerErrors} from "./IOrderSettlerErrors.sol";
import {ResolvedOrder, SettlementStatus} from "../base/SettlementStructs.sol";
import {SignedOrder} from "../../base/ReactorStructs.sol";

/// @notice Interface for cross-chain order settlers. These contracts collect escrow tokens from the swapper and filler
/// and consult an oracle to determine whether the cross-chain fill is completed within the valid fill timeframe. OrderSettlers
/// will vary by order type (i.e. dutch limit order) but one OrderSettler may receive orders for any target chain since
/// cross-chain SettlementOracles are outsourced to oracles of the swappers choice.
interface IOrderSettler is IOrderSettlerErrors {
    /// @notice Initiate a single order settlement using the given fill specification
    /// @param order The cross-chain order definition and valid signature to execute
    /// @param targetChainFiller Address reserved as the valid address to initiate the fill on the cross-chain settlementFiller
    function initiate(SignedOrder calldata order, address targetChainFiller) external;

    /// @notice Initiate a multiple order settlements using the given fill specification
    /// @param orders The cross-chain order definitions and valid signatures to execute
    /// @param targetChainFiller Address reserved as the valid address to initiate the fills on the cross-chain settlementFiller
    function initiateBatch(SignedOrder[] calldata orders, address targetChainFiller) external;

    /// @notice Finalize a settlement by first: confirming the cross-chain fill has happened and second: transferring
    /// input tokens and collateral to the filler. Finalize settlement only succeeds if the order has been filled
    /// successfully.
    /// @param orderId The order hash that identifies the order settlement to finalize
    function finalize(bytes32 orderId) external;

    /// @notice Cancels a settmentlent that was never filled after the settlement deadline. Input and collateral tokens
    /// are returned to swapper. Half of the filler collateral is shared if a challenger challenged the order.
    /// @param orderId The order hash that identifies the order settlement to cancel
    function cancel(bytes32 orderId) external;
}