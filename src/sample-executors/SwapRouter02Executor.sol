// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {Owned} from "solmate/src/auth/Owned.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {WETH} from "solmate/src/tokens/WETH.sol";
import {IReactorCallback} from "../interfaces/IReactorCallback.sol";
import {ResolvedOrder, ETH_ADDRESS} from "../base/ReactorStructs.sol";
import {ISwapRouter02} from "../external/ISwapRouter02.sol";
import {FundMaintenance} from "./FundMaintenance.sol";
import {ResolvedOrderLib} from "../lib/ResolvedOrderLib.sol";
import {Multicall} from "./Multicall.sol";

import "forge-std/console2.sol";

/// @notice A fill contract that uses SwapRouter02 to execute trades
contract SwapRouter02Executor is IReactorCallback, Multicall, FundMaintenance {
    using ResolvedOrderLib for ResolvedOrder;
    using SafeTransferLib for ERC20;

    error CallerNotWhitelisted();
    error MsgSenderNotReactor();
    error EtherSendFail();

    address private immutable whitelistedCaller;
    address private immutable reactor;

    constructor(address _whitelistedCaller, address _reactor, address _owner, address _swapRouter02)
        FundMaintenance(_swapRouter02, _owner)
    {
        whitelistedCaller = _whitelistedCaller;
        reactor = _reactor;
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
            ERC20(tokensToApproveForSwapRouter02[i]).approve(address(SWAP_ROUTER_02), type(uint256).max);
        }

        for (uint256 i = 0; i < tokensToApproveForReactor.length; i++) {
            ERC20(tokensToApproveForReactor[i]).approve(reactor, type(uint256).max);
        }

        SWAP_ROUTER_02.multicall(type(uint256).max, multicallData);

        // Send the appropriate amount of ETH back to reactor, so reactor can distribute to output recipients.
        uint256 ethToSendToReactor;
        for (uint256 i = 0; i < resolvedOrders.length;) {
            ethToSendToReactor += resolvedOrders[i].getTokenOutputAmount(ETH_ADDRESS);
            unchecked {
                i++;
            }
        }

        if (ethToSendToReactor > 0) {
            (bool sent,) = reactor.call{value: ethToSendToReactor}("");
            if (!sent) revert EtherSendFail();
        }
    }
}
