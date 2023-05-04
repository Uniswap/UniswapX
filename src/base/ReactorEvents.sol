// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/// @notice standardized events that should be emitted by all reactors
/// @dev collated into one library to help with forge expectEmit integration
/// @dev and for reactors which dont use base
contract ReactorEvents {
    /// @notice emitted when an order is filled
    /// @param orderHash The hash of the order that was filled
    /// @param filler The address which executed the fill
    /// @param nonce The nonce of the filled order
    /// @param offerer The offerer of the filled order
    event Fill(bytes32 indexed orderHash, address indexed filler, address indexed offerer, uint256 nonce);
}
