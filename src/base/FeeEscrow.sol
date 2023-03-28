// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {Owned} from "solmate/src/auth/Owned.sol";
import {CurrencyLibrary} from "../lib/CurrencyLibrary.sol";

/// @notice Escrow account for accrued fees
contract FeeEscrow is Owned(msg.sender) {
    using CurrencyLibrary for address;

    /// @notice Transfer tokens from the escrow to the recipient
    /// @param token The token to transfer
    /// @param recipient The recipient of the tokens
    /// @param amount The amount of tokens to transfer
    function transfer(address token, address recipient, uint256 amount) external onlyOwner {
        token.transfer(recipient, amount);
    }

    receive() external payable {}
}
