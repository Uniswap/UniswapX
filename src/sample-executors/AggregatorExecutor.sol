// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {Owned} from "solmate/src/auth/Owned.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IReactorCallback} from "../interfaces/IReactorCallback.sol";
import {ResolvedOrder} from "../base/ReactorStructs.sol";
import {ISwapRouter02} from "../external/ISwapRouter02.sol";
import {WETH} from "solmate/src/tokens/WETH.sol";

/// @notice A fill contract that uses the 1inch aggregator to execute trades
contract AggregatorExecutor is IReactorCallback, Owned {
    using SafeTransferLib for ERC20;

    error SwapFailed();
    error CallerNotWhitelisted();
    error MsgSenderNotReactor();
    error InsufficientWETHBalance();

    address private immutable aggregator;
    address private immutable whitelistedCaller;
    address private immutable reactor;

    ISwapRouter02 private immutable SWAP_ROUTER_02;
    WETH private immutable WETH9;

    constructor(
        address _whitelistedCaller,
        address _reactor,
        address _owner,
        address _aggregator,
        address _swapRouter02
    ) Owned(_owner) {
        whitelistedCaller = _whitelistedCaller;
        reactor = _reactor;
        aggregator = _aggregator;

        SWAP_ROUTER_02 = ISwapRouter02(_swapRouter02);
        WETH9 = WETH(payable(SWAP_ROUTER_02.WETH9()));
    }

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
    }

    /// @notice This function can be used to convert ERC20s to ETH that remains in this contract
    /// @notice We use SwapRouter02 for the swap.
    /// @param tokensToApprove Max approve these tokens to swapRouter02
    /// @param multicallData Pass into swapRouter02.multicall()
    function multicall(address[] calldata tokensToApprove, bytes[] calldata multicallData) external onlyOwner {
        unchecked {
            for (uint256 i = 0; i < tokensToApprove.length; i++) {
                ERC20(tokensToApprove[i]).approve(address(SWAP_ROUTER_02), type(uint256).max);
            }
        }

        SWAP_ROUTER_02.multicall(type(uint256).max, multicallData);
    }

    /// @notice Transfer all ETH in this contract to the recipient. Can only be called by owner.
    /// @param recipient The recipient of the ETH
    function withdrawETH(address recipient) external onlyOwner {
        SafeTransferLib.safeTransferETH(recipient, address(this).balance);
    }

    /// @notice Unwraps WETH to ETH and sends ETH to recipient.
    /// @param recipient The recipient of the ETH.
    function unwrapWETH(address recipient) external onlyOwner {
        uint256 balance = WETH9.balanceOf(address(this));

        if (balance == 0) revert InsufficientWETHBalance();

        WETH9.withdraw(balance);
        SafeTransferLib.safeTransferETH(recipient, balance);
    }

    receive() external payable {}
}
