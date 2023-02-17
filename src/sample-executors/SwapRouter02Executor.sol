// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {Owned} from "solmate/src/auth/Owned.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IReactorCallback} from "../interfaces/IReactorCallback.sol";
import {ResolvedOrder} from "../base/ReactorStructs.sol";
import {ISwapRouter02} from "../external/ISwapRouter02.sol";

/// @notice A fill contract that uses SwapRouter02 to execute trades
contract SwapRouter02Executor is IReactorCallback, Owned {
    using SafeTransferLib for ERC20;

    error CallerNotWhitelisted();
    error MsgSenderNotReactor();

    address private immutable swapRouter02;
    address private immutable whitelistedCaller;
    address private immutable reactor;

    constructor(address _whitelistedCaller, address _reactor, address _owner, address _swapRouter02) Owned(_owner) {
        whitelistedCaller = _whitelistedCaller;
        reactor = _reactor;
        swapRouter02 = _swapRouter02;
    }

    /// @param resolvedOrders The orders to fill
    /// @param filler This filler must be `whitelistedCaller`
    /// @param fillData It has the below encoded:
    /// address[] memory tokensToApproveForSwapRouter02: Max approve these tokens to swapRouter02
    /// address[] memory tokensToApproveForReactor: Max approve these tokens to reactor
    /// bytes[] memory multicallData: Pass into swapRouter02.multicall()
    function reactorCallback(ResolvedOrder[] calldata resolvedOrders, address filler, bytes calldata fillData)
        external
    {
        if (msg.sender != reactor) {
            revert MsgSenderNotReactor();
        }
        if (filler != whitelistedCaller) {
            revert CallerNotWhitelisted();
        }
        (
            address[] memory tokensToApproveForSwapRouter02,
            address[] memory tokensToApproveForReactor,
            bytes[] memory multicallData
        ) = abi.decode(fillData, (address[], address[], bytes[]));

        for (uint256 i = 0; i < tokensToApproveForSwapRouter02.length; i++) {
            ERC20(tokensToApproveForSwapRouter02[i]).approve(swapRouter02, type(uint256).max);
        }

        for (uint256 i = 0; i < tokensToApproveForReactor.length; i++) {
            ERC20(tokensToApproveForReactor[i]).approve(reactor, type(uint256).max);
        }

        ISwapRouter02(swapRouter02).multicall(type(uint256).max, multicallData);
    }

    /// @notice This function can be used to convert ERC20s to ETH that remains in this contract
    /// @param tokensToApprove Max approve these tokens to swapRouter02
    /// @param multicallData Pass into swapRouter02.multicall()
    function multicall(address[] calldata tokensToApprove, bytes[] calldata multicallData) external onlyOwner {
        for (uint256 i = 0; i < tokensToApprove.length; i++) {
            ERC20(tokensToApprove[i]).approve(swapRouter02, type(uint256).max);
        }
        ISwapRouter02(swapRouter02).multicall(type(uint256).max, multicallData);
    }

    /// @notice Transfer all ETH in this contract to the recipient. Can only be called by owner.
    /// @param recipient The recipient of the ETH
    function withdrawETH(address recipient) external onlyOwner {
        SafeTransferLib.safeTransferETH(recipient, address(this).balance);
    }
    receive() external payable {}
}
