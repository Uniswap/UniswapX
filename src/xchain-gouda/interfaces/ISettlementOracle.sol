// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {OutputToken} from "../base/SettlementStructs.sol";
import {SignedOrder} from "../../base/ReactorStructs.sol";

/// @notice Interface for cross chain listener oracles for cross-chain gouda
interface ISettlementOracle {
    /// @notice Get the output tokens filled associated with a orderId
    /// @param orderId The order hash that identifies the order that was filled
    /// @param crossChainFiller The address on the target chain that is responsible for filling the order
    /// @return filledOutputs An array of all the output tokens that were filled on the target chain
    function getSettlementFillInfo(bytes32 orderId, address crossChainFiller)
        external
        view
        returns (OutputToken[] calldata filledOutputs);

    /// @notice Logs the settlement info given for a orderId
    /// @dev Access to this function must be restricted to valid message bridges, and must verify that the cross chain
    /// message was sent by a valid SettlementFiller on the target chain of output tokens.
    /// @param orderId The order hash that identifies the order that was filled
    /// @param crossChainFiller The address that initiated the fill on SettlementFiller
    /// @param outputs The output tokens that were filled on the target chain.
    function logSettlementFillInfo(bytes32 orderId, address crossChainFiller, OutputToken[] calldata outputs)
        external;
}
