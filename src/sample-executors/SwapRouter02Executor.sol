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
    address private immutable reactor;

    constructor(address _whitelistedCaller, address _reactor, address _owner) Owned(_owner) {
        whitelistedCaller = _whitelistedCaller;
        reactor = _reactor;
    }

    function reactorCallback(ResolvedOrder[] calldata resolvedOrders, address filler, bytes calldata fillData)
        external
    {
        if (filler != whitelistedCaller) {
            revert CallerNotWhitelisted();
        }
        (
            address[] memory tokensToApproveForSwapRouter02,
            address[] memory tokensToApproveForReactor,
            bytes[] memory multicallData
        ) = abi.decode(fillData, (address[], address[], bytes[]));
        if (tokensToApproveForSwapRouter02.length > 0) {
            for (uint256 i = 0; i < tokensToApproveForSwapRouter02.length; i++) {
                ERC20(tokensToApproveForSwapRouter02[i]).approve(swapRouter02, type(uint256).max);
            }
        }
        if (tokensToApproveForReactor.length > 0) {
            for (uint256 i = 0; i < tokensToApproveForReactor.length; i++) {
                ERC20(tokensToApproveForReactor[i]).approve(reactor, type(uint256).max);
            }
        }
        ISwapRouter02(swapRouter02).multicall(type(uint256).max, multicallData);
    }

    function multicall(address[] calldata tokensToApproveForSwapRouter02, bytes[] calldata multicallData)
        external
        onlyOwner
    {
        if (tokensToApproveForSwapRouter02.length > 0) {
            for (uint256 i = 0; i < tokensToApproveForSwapRouter02.length; i++) {
                ERC20(tokensToApproveForSwapRouter02[i]).approve(swapRouter02, type(uint256).max);
            }
        }
        ISwapRouter02(swapRouter02).multicall(type(uint256).max, multicallData);
    }
}
