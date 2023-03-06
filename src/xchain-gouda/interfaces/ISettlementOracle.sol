// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {OutputToken} from "../base/SettlementStructs.sol";
import {SignedOrder} from "../../base/ReactorStructs.sol";

/// @notice Interface for cross chain listener oracles for cross-chain gouda
interface ISettlementOracle {
    /// @notice finalize a settlement
    /// @dev Access to this function must be restricted to valid message bridges, and must verify that the cross chain
    /// message was sent by a valid SettlementFiller on the target chain of output tokens.
    /// @param orderId The order hash that identifies the order that was filled
    /// @param settler The settler contract the oracle should call to finalize the settlement
    /// @param targetChainFiller The address that initiated the fill on SettlementFiller
    /// @param fillTimestamp The time in which the order was filled on the target chain
    /// @param outputs The output tokens that were filled on the target chain.
    function finalizeSettlement(
        bytes32 orderId,
        address settler,
        address targetChainFiller,
        uint256 fillTimestamp,
        OutputToken[] calldata outputs
    ) external;
}
