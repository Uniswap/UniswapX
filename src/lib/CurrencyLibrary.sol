// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {SafeCast} from "openzeppelin-contracts/utils/math/SafeCast.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";

address constant NATIVE = 0x0000000000000000000000000000000000000000;

/// @title CurrencyLibrary
/// @dev This library allows for transferring native ETH and ERC20s via direct taker OR fill contract.
library CurrencyLibrary {
    using SafeTransferLib for ERC20;

    /// @notice Thrown when a native transfer fails
    error NativeTransferFailed();
    error NotEnoughETHDirectTaker();

    /// @notice Get the balance of a currency for addr
    /// @param currency The currency to get the balance of
    /// @param addr The address to get the balance of
    /// @return balance The balance of the currency for addr
    function balanceOf(address currency, address addr) internal view returns (uint256 balance) {
        if (isNative(currency)) {
            balance = addr.balance;
        } else {
            balance = ERC20(currency).balanceOf(addr);
        }
    }

    /// @notice Transfer currency to recipient
    /// @param currency The currency to transfer
    /// @param recipient The recipient of the currency
    /// @param amount The amount of currency to transfer
    function transfer(address currency, address recipient, uint256 amount) internal {
        if (isNative(currency)) {
            (bool success,) = recipient.call{value: amount}("");
            if (!success) revert NativeTransferFailed();
        } else {
            ERC20(currency).safeTransfer(recipient, amount);
        }
    }

    /// @notice Transfer currency from msg.sender to the recipient
    /// @dev if currency is ETH, the value must have been sent in the execute call and is transferred directly
    /// @dev if currency is token, the value is transferred from msg.sender via permit2
    /// @param currency The currency to transfer
    /// @param recipient The recipient of the currency
    /// @param amount The amount of currency to transfer
    /// @param permit2 The deployed permit2 address
    function transferFromDirectTaker(address currency, address recipient, uint256 amount, IAllowanceTransfer permit2)
        internal
    {
        if (isNative(currency)) {
            if (msg.value < amount) revert NotEnoughETHDirectTaker();
            (bool success,) = recipient.call{value: amount}("");
            if (!success) revert NativeTransferFailed();
        } else {
            permit2.transferFrom(msg.sender, recipient, SafeCast.toUint160(amount), currency);
        }
    }

    /// @notice returns true if currency is native
    /// @param currency The currency to check
    /// @return true if currency is native
    function isNative(address currency) internal pure returns (bool) {
        return currency == NATIVE;
    }
}
