// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

/// @notice standardized events that should be emitted by all cross-chain reactors
/// @dev collated into one library to help with forge expectEmit integration
/// @dev and for reactors which dont use base
contract SettlementEvents {
    /// @notice emitted when a settlement is initiated
    /// @param orderHash The hash of the order to be filled
    /// @param offerer The offerer of the filled order
    /// @param originChainFiller The address that initiates the settlement and recieves input tokens once the order is filled
    /// @param targetChainFiller The address that fills the order on the target chain
    /// @param settlementOracle The settlementOracle to be used to determine fulfillment of order
    /// @param optimisticDeadline The timestamp starting at which the settlement may be cancelled if not filled
    /// @param challengeDeadline The timestamp starting at which the settlement may be cancelled if not filled
    event InitiateSettlement(
        bytes32 indexed orderHash,
        address indexed originChainFiller,
        address indexed offerer,
        address targetChainFiller,
        address settlementOracle,
        uint256 fillDeadline,
        uint256 optimisticDeadline,
        uint256 challengeDeadline
    );

    /// @notice emitted when a settlement has been filled successfully
    event FinalizeSettlement(bytes32 indexed orderId);

    /// @notice emitted when a settlement has been cancelled
    event CancelSettlement(bytes32 indexed orderId);

    /// @notice emitted when a settlement has been challenged
    event SettlementChallenged(bytes32 indexed orderId, address indexed challenger);
}
