// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {CurrencyLibrary} from "../lib/CurrencyLibrary.sol";

/// @notice Escrow account for accrued fees
contract FeeEscrow {
    using CurrencyLibrary for address;

    /// @notice Thrown when an unauthorized party attempts to transfer funds
    error Unauthorized();

    /// @notice The owner of the escrow which can transfer funds
    address private immutable owner;

    constructor() {
        owner = msg.sender;
    }

    /// @notice Modifier to restrict access to the owner
    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert Unauthorized();
        }
        _;
    }

    /// @notice Transfer tokens from the escrow to the recipient
    /// @param token The token to transfer
    /// @param recipient The recipient of the tokens
    /// @param amount The amount of tokens to transfer
    function transfer(address token, address recipient, uint256 amount) external onlyOwner {
        token.transfer(recipient, amount);
    }

    receive() external payable {}
}
