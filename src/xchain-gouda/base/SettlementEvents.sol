// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {InputToken} from "../../base/ReactorStructs.sol";
import {CollateralToken} from "./SettlementStructs.sol";

/// @notice standardized events that should be emitted by all cross-chain reactors
/// @dev collated into one library to help with forge expectEmit integration
/// @dev and for reactors which dont use base
contract SettlementEvents {
    /// @notice emitted when a settlement is initiated. Has all the information needed to construct the associated SettlementKey
    /// @param orderHash The hash of the order to be filled
    /// @param offerer The offerer of the filled order
    /// @param filler The address that initiates the settlement and recieves input tokens once the order is filled on the target chain
    event InitiateSettlement(
        bytes32 indexed orderHash,
        address indexed offerer,
        address indexed filler
    );

    /// @notice emitted when a settlement has been filled successfully
    /// @param orderId The hash of the order to be finalized
    event FinalizeSettlement(bytes32 indexed orderId);

    /// @notice emitted when a settlement has been cancelled
    /// @param orderId The hash of the order to be cancelled
    event CancelSettlement(bytes32 indexed orderId);

    /// @notice emitted when a settlement has been challenged
    /// @param orderId The hash of the order to be challenged
    /// @param challenger The address of the account that has challenged the settlement fill
    event SettlementChallenged(bytes32 indexed orderId, address indexed challenger);
}
