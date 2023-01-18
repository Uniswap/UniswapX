// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {OutputToken} from "../base/SettlementStructs.sol";
import {SignedOrder} from "../../base/ReactorStructs.sol";

/// @notice Interface for cross chain fillers for gouda
interface ISettlementFiller {
    /// @notice Fills an order and transmits a message to the origin chain about the details of the fulfillment including
    /// the settlementId and the outputs
    /// @dev This function must form the settlementId by keccak256-ing the orderId and msg.sender together to guarantee
    /// exclusive access to this settlement from the expected filler
    /// @param orderId The cross-chain orderId
    /// @param outputs The outputs associated with the corresponding settlement. The outputs MUST be in the same order
    /// as they are in the original order.
    function fillAndTransmitSettlementOutputs(bytes32 orderId, OutputToken[] calldata outputs) external;
}
