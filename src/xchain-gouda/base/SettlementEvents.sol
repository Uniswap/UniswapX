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
    /// @param settlementOracle The settlementOracle to be used to determine fulfillment of order
    /// @param optimisticDeadline The timestamp starting at which the settlement may be cancelled if not filled
    /// @param challengeDeadline The timestamp starting at which the settlement may be cancelled if not filled
    /// @param input The InputToken information associated with the order
    /// @param fillerCollateral The CollateralToken information associated the filler collateral
    /// @param challengerCollateral The CollateralToken information associated the challenger collateral
    /// @param outputsHash A hash of the array of OutputToken parameters associated with the order
    event InitiateSettlement(
        bytes32 indexed orderHash,
        address indexed offerer,
        address indexed filler,
        address settlementOracle,
        uint256 fillDeadline,
        uint256 optimisticDeadline,
        uint256 challengeDeadline,
        InputToken input,
        CollateralToken fillerCollateral,
        CollateralToken challengerCollateral,
        bytes32 outputsHash
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
