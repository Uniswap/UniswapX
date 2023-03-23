// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {Owned} from "solmate/src/auth/Owned.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {WETH} from "solmate/src/tokens/WETH.sol";
import {IReactorCallback} from "../interfaces/IReactorCallback.sol";
import {CurrencyLibrary} from "../lib/CurrencyLibrary.sol";
import {ResolvedOrder, OutputToken} from "../base/ReactorStructs.sol";
import {ISwapRouter02} from "../external/ISwapRouter02.sol";
import {FundMaintenance} from "./FundMaintenance.sol";
import {Multicall} from "./Multicall.sol";

/// @notice A fill contract that uses SwapRouter02 to execute trades
contract SwapRouter02Executor is IReactorCallback, Multicall, FundMaintenance {
    using SafeTransferLib for ERC20;
    using CurrencyLibrary for address;

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

        (address[] memory tokensToApproveForSwapRouter02, bytes[] memory multicallData) =
            abi.decode(fillData, (address[], bytes[]));

        for (uint256 i = 0; i < tokensToApproveForSwapRouter02.length; i++) {
            ERC20(tokensToApproveForSwapRouter02[i]).approve(address(SWAP_ROUTER_02), type(uint256).max);
        }

        SWAP_ROUTER_02.multicall(type(uint256).max, multicallData);

        for (uint256 i = 0; i < resolvedOrders.length; i++) {
            ResolvedOrder memory order = resolvedOrders[i];
            for (uint256 j = 0; j < order.outputs.length; j++) {
                OutputToken memory output = order.outputs[j];
                output.token.transfer(output.recipient, output.amount);
            }
        }
    }
}
