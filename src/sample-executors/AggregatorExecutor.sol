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
    error SwapFailed();
    error CallerNotWhitelisted();
    error MsgSenderNotReactor();
    error EtherSendFail();

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

        (bool success,) = aggregator.call(swapData);
        if (!success) revert SwapFailed();

        // handle eth output
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
