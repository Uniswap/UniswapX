// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {ResolvedOrder} from "../base/SettlementStructs.sol";
import {SignedOrder} from "../../base/ReactorStructs.sol";
import {SettlementFillInfo} from "./ICrossChainListener.sol.";

/// @notice Interface for cross chain fillers for gouda
interface ICrossChainFiller {
    /// @notice Fills an order and transmits a message to the origin chain about the details of the fulfillment
    /// @param orderId The cross-chain orderId
    /// @param recipient The recipient of the funds
    /// @param token The address of the token being spent
    /// @param amount The amount of token to send to the recipient
    /// @param orderId The cross-chain orderId
    /// @return settlementInfo The settlmentInfo that was passed to the cross-chain listener from a valid source
    function fillAndTransmitSettlementInfo(bytes32 orderId, address recipient, address, token, address amount)
        external
        view
        returns (SettlementFillInfo[] calldata);
}
