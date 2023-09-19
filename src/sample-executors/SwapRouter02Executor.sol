// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Owned} from "solmate/src/auth/Owned.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {WETH} from "solmate/src/tokens/WETH.sol";
import {IReactorCallback} from "../interfaces/IReactorCallback.sol";
import {IReactor} from "../interfaces/IReactor.sol";
import {CurrencyLibrary} from "../lib/CurrencyLibrary.sol";
import {ResolvedOrder, OutputToken, SignedOrder} from "../base/ReactorStructs.sol";
import {ISwapRouter02} from "../external/ISwapRouter02.sol";
import {BaseExecutor} from "./BaseExecutor.sol";

/// @notice A fill contract that uses SwapRouter02 to execute trades
contract SwapRouter02Executor is BaseExecutor {
    using SafeTransferLib for ERC20;
    using CurrencyLibrary for address;

    /// @notice thrown if reactorCallback is called with a non-whitelisted filler
    error CallerNotWhitelisted();
    /// @notice thrown if reactorCallback is called by an address other than the reactor
    error MsgSenderNotReactor();

    ISwapRouter02 public immutable swapRouter02;
    address public immutable whitelistedCaller;
    WETH public immutable weth;

    modifier onlyWhitelistedCaller() {
        if (msg.sender != whitelistedCaller) {
            revert CallerNotWhitelisted();
        }
        _;
    }

    modifier onlyReactor() {
        if (msg.sender != address(reactor)) {
            revert MsgSenderNotReactor();
        }
        _;
    }

    constructor(address _whitelistedCaller, IReactor _reactor, address _owner, ISwapRouter02 _swapRouter02)
        BaseExecutor(_reactor, _owner)
    {
        whitelistedCaller = _whitelistedCaller;
        swapRouter02 = _swapRouter02;
        weth = WETH(payable(_swapRouter02.WETH9()));
    }

    function multicall(bytes[] calldata data) public payable override onlyWhitelistedCaller returns (bytes[] memory) {
        return super.multicall(data);
    }

    /// @notice fill UniswapX orders using SwapRouter02
    /// @param callbackData It has the below encoded:
    /// address[] memory tokensToApproveForSwapRouter02: Max approve these tokens to swapRouter02
    /// address[] memory tokensToApproveForReactor: Max approve these tokens to reactor
    /// bytes[] memory multicallData: Pass into swapRouter02.multicall()
    function reactorCallback(ResolvedOrder[] calldata, bytes calldata callbackData) external override onlyReactor {
        (
            address[] memory tokensToApproveForSwapRouter02,
            address[] memory tokensToApproveForReactor,
            bytes[] memory multicallData
        ) = abi.decode(callbackData, (address[], address[], bytes[]));

        unchecked {
            for (uint256 i = 0; i < tokensToApproveForSwapRouter02.length; i++) {
                ERC20(tokensToApproveForSwapRouter02[i]).safeApprove(address(swapRouter02), type(uint256).max);
            }

            for (uint256 i = 0; i < tokensToApproveForReactor.length; i++) {
                ERC20(tokensToApproveForReactor[i]).safeApprove(address(reactor), type(uint256).max);
            }
        }

        swapRouter02.multicall(type(uint256).max, multicallData);

        // transfer any native balance to the reactor
        // it will refund any excess
        if (address(this).balance > 0) {
            CurrencyLibrary.transferNative(address(reactor), address(this).balance);
        }
    }

    /// @notice This function can be used to convert ERC20s to ETH that remains in this contract
    /// @param tokensToApprove Max approve these tokens to swapRouter02
    /// @param multicallData Pass into swapRouter02.multicall()
    function swapRouter02Multicall(ERC20[] calldata tokensToApprove, bytes[] calldata multicallData)
        external
        onlyOwner
    {
        for (uint256 i = 0; i < tokensToApprove.length; i++) {
            tokensToApprove[i].safeApprove(address(swapRouter02), type(uint256).max);
        }
        swapRouter02.multicall(type(uint256).max, multicallData);
    }

    /// @notice Unwraps the contract's WETH9 balance and sends it to the recipient as ETH. Can only be called by owner.
    /// @param recipient The address receiving ETH
    function unwrapWETH(address recipient) external onlyOwner {
        uint256 balanceWETH = weth.balanceOf(address(this));

        weth.withdraw(balanceWETH);
        SafeTransferLib.safeTransferETH(recipient, address(this).balance);
    }

    /// @notice Transfer all ETH in this contract to the recipient. Can only be called by owner.
    /// @param recipient The recipient of the ETH
    function withdrawETH(address recipient) external onlyOwner {
        SafeTransferLib.safeTransferETH(recipient, address(this).balance);
    }
}
