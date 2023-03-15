// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {OutputToken, SettlementKey} from "../base/SettlementStructs.sol";
import {SignedOrder} from "../../base/ReactorStructs.sol";

/// @notice Interface for cross chain listener oracles for cross-chain gouda
interface ISettlementOracle {
    /// @notice finalize a settlement
    /// @dev Access to this function must be restricted to valid message bridges, and must verify that the cross chain
    /// message was sent by a valid SettlementFiller on the target chain of output tokens.
    /// @param orderHash The order hash that identifies the order that was filled
    /// @param key The SettlementKey containing all immutable info pertaining to a settlement
    /// @param settler The settler contract the oracle should call to finalize the settlement
    /// @param fillTimestamp The time in which the order was filled on the target chain
    function finalizeSettlement(bytes32 orderHash, SettlementKey memory key, address settler, uint256 fillTimestamp)
        external;
}
