// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {IReactorCallback} from "../interfaces/IReactorCallback.sol";
import {ResolvedOrder, OutputToken} from "../base/ReactorStructs.sol";
import {Multicall} from "./Multicall.sol";
import {FundMaintenance} from "./FundMaintenance.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ResolvedOrderLib} from "../lib/ResolvedOrderLib.sol";
import {CurrencyLibrary, ETH_ADDRESS} from "../lib/CurrencyLibrary.sol";

/// @notice A fill contract that uses the 1inch aggregator to execute trades
contract AggregatorExecutor is IReactorCallback, Multicall, FundMaintenance {
    using ResolvedOrderLib for ResolvedOrder;
    using CurrencyLibrary for address;

    error SwapFailed(bytes err);
    error CallerNotWhitelisted();
    error MsgSenderNotReactor();
    error EtherSendFail();
    error InsufficientTokenBalance();
    error InsufficientEthBalance();

    address private immutable aggregator;
    address private immutable whitelistedCaller;
    address private immutable reactor;

    constructor(
        address _whitelistedCaller,
        address _reactor,
        address _owner,
        address _aggregator,
        address _swapRouter02
    ) FundMaintenance(_swapRouter02, _owner) {
        whitelistedCaller = _whitelistedCaller;
        reactor = _reactor;
        aggregator = _aggregator;
    }

    /// @notice This safely handles orders with only one output token. Do not use for orders that have more than one output token.
    /// @param resolvedOrders The orders to fill
    /// @param filler This filler must be `whitelistedCaller`
    /// @param fillData It has the below encoded:
    /// address[] memory tokensToApproveForAggregator: Max approve these tokens to the 1 inch contract
    /// address[] memory tokensToApproveForReactor: Max approve these tokens to reactor
    /// bytes memory swapData: Calldata for the aggregator.unoswap() function
    function reactorCallback(ResolvedOrder[] calldata resolvedOrders, address filler, bytes calldata fillData)
        external
    {
        if (msg.sender != reactor) {
            revert MsgSenderNotReactor();
        }
        if (filler != whitelistedCaller) {
            revert CallerNotWhitelisted();
        }
        (address[] memory tokensToApproveForAggregator, bytes memory swapData) =
            abi.decode(fillData, (address[], bytes));

        unchecked {
            for (uint256 i = 0; i < tokensToApproveForAggregator.length; i++) {
                ERC20(tokensToApproveForAggregator[i]).approve(aggregator, type(uint256).max);
            }
        }

        // Require that there is only one output per order.
        // Note: We are doing repeated checks if there are repeated tokens.
        (uint256[] memory balanceBefore, uint256 balanceEthBefore) = getBalancesBeforeCall(resolvedOrders);

        (bool success, bytes memory returnData) = aggregator.call(swapData);
        if (!success) revert SwapFailed(returnData);

        verifyBalancesAfterCall(resolvedOrders, balanceBefore, balanceEthBefore);

        // Balance checking on this contract must happen before transfer is called.
        for (uint256 i = 0; i < resolvedOrders.length; i++) {
            ResolvedOrder memory order = resolvedOrders[i];
            for (uint256 j = 0; j < order.outputs.length; j++) {
                OutputToken memory output = order.outputs[j];
                output.token.transfer(output.recipient, output.amount);
            }
        }
    }

    function getBalancesBeforeCall(ResolvedOrder[] memory resolvedOrders)
        private
        view
        returns (uint256[] memory balanceBefore, uint256 balanceEthBefore)
    {
        balanceBefore = new uint256[](resolvedOrders.length);
        bool containsEthOutput = false;
        for (uint256 i = 0; i < resolvedOrders.length; i++) {
            if (resolvedOrders[i].outputs[0].token == ETH_ADDRESS) {
                containsEthOutput = true;
                continue;
            }
            balanceBefore[i] = ERC20(resolvedOrders[i].outputs[0].token).balanceOf(address(this));
        }
        if (containsEthOutput) {
            balanceEthBefore = address(this).balance;
        }
    }

    function verifyBalancesAfterCall(
        ResolvedOrder[] memory resolvedOrders,
        uint256[] memory balanceBefore,
        uint256 balanceEthBefore
    ) private view {
        uint256 balanceEthRequested;
        for (uint256 i = 0; i < resolvedOrders.length; i++) {
            if (resolvedOrders[i].outputs[0].token == ETH_ADDRESS) {
                if (balanceEthRequested == 0) {
                    balanceEthRequested = resolvedOrders[i].getTokenOutputAmount(ETH_ADDRESS);
                }
                continue;
            }
            uint256 balanceAfter = ERC20(resolvedOrders[i].outputs[0].token).balanceOf(address(this));
            uint256 balanceRequested = resolvedOrders[i].getTokenOutputAmount(resolvedOrders[i].outputs[0].token);
            int256 balanceAllowed = int256(balanceAfter - balanceBefore[i]);
            if (balanceAllowed < 0 || uint256(balanceAllowed) < balanceRequested) revert InsufficientTokenBalance();
        }
        if (balanceEthRequested > 0) {
            int256 balanceEthAllowed = int256(address(this).balance - balanceEthBefore);
            if (balanceEthAllowed < 0 || uint256(balanceEthAllowed) < balanceEthRequested) {
                revert InsufficientEthBalance();
            }
        }
    }
}
