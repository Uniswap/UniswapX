// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {OutputToken} from "../base/SettlementStructs.sol";
import {SignedOrder} from "../../base/ReactorStructs.sol";

/// @notice Interface for cross chain listener oracles for cross-chain gouda
interface ISettlementOracle {
    /// @notice Get the output tokens filled associated with a settlementId
    /// @param settlementId The cross-chain settlementId which is a hash of the orderId and crossChainFiller address
    function getSettlementFillInfo(bytes32 settlementId) external view returns (OutputToken[] calldata);

    /// @notice Logs the settlement info given for a settlementId
    /// @dev Access to this function must be restricted to valid message bridges, and must verify that the cross chain
    /// message was sent by a valid SettlementFiller on the target chain of output tokens.
    /// @param outputs The output tokens that were filled on the target chain.
    /// @param settlementId The cross-chain settlementId which is a hash of the orderId and crossChainFiller address
    function logSettlementFillInfo(OutputToken[] calldata outputs, bytes32 settlementId) external;
}
