// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {Owned} from "solmate/src/auth/Owned.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IReactorCallback} from "../interfaces/IReactorCallback.sol";
import {ResolvedOrder} from "../base/ReactorStructs.sol";
import {ISwapRouter02} from "../external/ISwapRouter02.sol";

contract SwapRouter02Executor is IReactorCallback, Owned {
    using SafeTransferLib for ERC20;

    error CallerNotWhitelisted();

    address private constant swapRouter02 = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
    address private immutable whitelistedCaller;

    constructor(address _whitelistedCaller, address _owner) Owned(_owner) {
        whitelistedCaller = _whitelistedCaller;
    }

    /// @dev Can handle multiple resolvedOrders, but the input tokens and output tokens must be the same.
    function reactorCallback(
        ResolvedOrder[] calldata resolvedOrders,
        address filler, //filler
        bytes calldata fillData
    ) external {
        if (filler != whitelistedCaller) {
            revert CallerNotWhitelisted();
        }
        (address[] memory tokensToApprove, bytes[] memory multicallData) = abi.decode(fillData, (address[], bytes[]));
    }

    /// @notice tranfer any earned tokens to the owner
    function claimTokens(ERC20 token) external onlyOwner {
        token.safeTransfer(owner, token.balanceOf(address(this)));
    }
}
