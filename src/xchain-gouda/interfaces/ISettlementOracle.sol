// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {OutputToken} from "../base/SettlementStructs.sol";
import {SignedOrder} from "../../base/ReactorStructs.sol";

/// @notice Interface for cross chain listener oracles for cross-chain gouda
interface ISettlementOracle {
    /// @notice Get the output tokens filled associated with a orderId
    /// @param orderId The order hash that identifies the order that was filled
    /// @param targetChainFiller The address on the target chain that is responsible for filling the order
    /// @return filledOutputs An array of all the output tokens that were filled on the target chain
    function getSettlementInfo(bytes32 orderId, address targetChainFiller)
        external
        view
        returns (OutputToken[] calldata filledOutputs, uint256 fillTimestamp);

    /// @notice Logs the settlement info given for a orderId
    /// @dev Access to this function must be restricted to valid message bridges, and must verify that the cross chain
    /// message was sent by a valid SettlementFiller on the target chain of output tokens.
    /// @param orderId The order hash that identifies the order that was filled
    /// @param targetChainFiller The address that initiated the fill on SettlementFiller
    /// @param fillTimestamp The time in which the order was filled on the target chain
    /// @param outputs The output tokens that were filled on the target chain.
    function logSettlementInfo(
        bytes32 orderId,
        address targetChainFiller,
        uint256 fillTimestamp,
        OutputToken[] calldata outputs
    ) external;
}
