// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

/// @notice standardized events that should be emitted by all cross-chain reactors
/// @dev collated into one library to help with forge expectEmit integration
/// @dev and for reactors which dont use base
contract XReactorEvents {
    /// @notice emitted when a settlement is initiated
    /// @param orderHash The hash of the order that was filled
    /// @param offerer The offerer of the filled order
    /// @param settlementOracle The offerer of the filled order
    /// @param nonce The nonce of the filled order
    event InitiateSettlement(bytes32 indexed orderHash, address indexed offerer, address indexed settlementOracle, uint256 nonce);
}
