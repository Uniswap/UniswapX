// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {OutputToken} from "../base/SettlementStructs.sol";
import {SignedOrder} from "../../base/ReactorStructs.sol";

/// @notice Interface for cross chain fillers for gouda. A SettlementFiller exists on the target chain, and carries out
/// transfers from the crossChainFiller to the output recipients in order to verify the stated outputs were filled successfully
interface ISettlementFiller {
    /// @notice Fills an order on the target chain and transmits a message to the origin chain about the details of the
    /// fulfillment including the orderId and the outputs
    /// @dev This function must call the valid bridge to transmit the orderId, msg.sender, and outputs to the origin chain
    /// @param orderId The cross-chain orderId
    /// @param outputs The outputs associated with the corresponding settlement. The outputs MUST be in the same order
    /// as they are in the original order, or else the order will not resolve as filled.
    function fillAndTransmitSettlementOutputs(bytes32 orderId, OutputToken[] calldata outputs) external;
}
