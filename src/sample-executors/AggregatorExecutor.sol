// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {IReactorCallback} from "../interfaces/IReactorCallback.sol";
import {ResolvedOrder, ETH_ADDRESS} from "../base/ReactorStructs.sol";
import {Multicall} from "./Multicall.sol";
import {FundMaintenance} from "./FundMaintenance.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ResolvedOrderLib} from "../lib/ResolvedOrderLib.sol";

/// @notice A fill contract that uses the 1inch aggregator to execute trades
contract AggregatorExecutor is IReactorCallback, Multicall, FundMaintenance {
    error SwapFailed(bytes error);
    error CallerNotWhitelisted();
    error MsgSenderNotReactor();
    error EtherSendFail();
    error InsufficientTokenBalance();

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

    using ResolvedOrderLib for ResolvedOrder;

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
        (
            address[] memory tokensToApproveForAggregator,
            address[] memory tokensToApproveForReactor,
            bytes memory swapData
        ) = abi.decode(fillData, (address[], address[], bytes));

        unchecked {
            for (uint256 i = 0; i < tokensToApproveForAggregator.length; i++) {
                ERC20(tokensToApproveForAggregator[i]).approve(aggregator, type(uint256).max);
            }
            for (uint256 i = 0; i < tokensToApproveForReactor.length; i++) {
                ERC20(tokensToApproveForReactor[i]).approve(reactor, type(uint256).max);
            }
        }

        // Require that there is only one output per order.
        // Note: We are doing repeated checks if there are repeated tokens.
        uint256[] memory balanceBefore = new uint256[](resolvedOrders.length);
        for (uint256 i = 0; i < resolvedOrders.length;) {
            balanceBefore[i] = ERC20(resolvedOrders[i].outputs[0].token).balanceOf(address(this));

            unchecked {
                i++;
            }
        }

        (bool success, bytes memory returnData) = aggregator.call(swapData);
        if (!success) revert SwapFailed(returnData);

        for (uint256 i = 0; i < resolvedOrders.length;) {
            uint256 balanceAfter = ERC20(resolvedOrders[i].outputs[0].token).balanceOf(address(this));
            uint256 balanceRequested = resolvedOrders[i].getTokenOutputAmount(resolvedOrders[i].outputs[0].token);
            int256 delta = int256(balanceAfter - balanceBefore[i]);
            if (delta < 0 || uint256(delta) < balanceRequested) revert InsufficientTokenBalance();
            unchecked {
                i++;
            }
        }

        // handle eth output
        uint256 ethToSendToReactor;
        // uint256 wethRequested;
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
