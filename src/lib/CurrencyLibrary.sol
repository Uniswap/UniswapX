// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.17;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ETH_ADDRESS} from "../base/ReactorStructs.sol";
import {BaseReactor} from "../reactors/BaseReactor.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {SafeCast} from "openzeppelin-contracts/utils/math/SafeCast.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";

/// @title CurrencyLibrary
/// @dev This library allows for transferring and holding native tokens and ERC20 tokens
library CurrencyLibrary {
    using SafeTransferLib for ERC20;

    /// @notice Thrown when a native transfer fails
    error NativeTransferFailed();

    function transfer(
        address token,
        address recipient,
        uint256 amount,
        address fillContract,
        IAllowanceTransfer permit2
    ) internal {
        if (token == ETH_ADDRESS) {
            (bool success,) = recipient.call{value: amount}("");
            if (!success) revert NativeTransferFailed();
        } else {
            if (fillContract == address(1)) {
                permit2.transferFrom(msg.sender, recipient, SafeCast.toUint160(amount), token);
            } else {
                ERC20(token).safeTransferFrom(fillContract, recipient, amount);
            }
        }
    }
}
