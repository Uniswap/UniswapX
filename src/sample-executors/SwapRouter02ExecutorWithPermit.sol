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
import {SwapRouter02Executor} from "./SwapRouter02Executor.sol";

/// @notice A fill contract that uses SwapRouter02 to execute trades
contract SwapRouter02ExecutorWithPermit is SwapRouter02Executor {
    constructor(address _whitelistedCaller, IReactor _reactor, address _owner, ISwapRouter02 _swapRouter02)
        SwapRouter02Executor(_whitelistedCaller, _reactor, _owner, _swapRouter02)
    {}

    /// @notice assume that we already have all output tokens
    /// @dev assume 2612 permit is collected offchain
    function executeWithPermit(SignedOrder calldata order, bytes calldata callbackData, bytes calldata permitData)
        external
        onlyWhitelistedCaller
    {
        _permit(permitData);
        reactor.executeWithCallback(order, callbackData);
    }

    /// @notice assume that we already have all output tokens
    /// @dev assume 2612 permits are collected offchain
    function executeBatchWithPermit(
        SignedOrder[] calldata orders,
        bytes calldata callbackData,
        bytes[] calldata permitData
    ) external onlyWhitelistedCaller {
        _permitBatch(permitData);
        reactor.executeBatchWithCallback(orders, callbackData);
    }

    /// @notice execute a signed 2612-style permit
    /// the transaction will revert if the permit cannot be executed
    /// must be called before the call to the reactor
    function _permit(bytes calldata permitData) internal {
        (address token, bytes memory data) = abi.decode(permitData, (address, bytes));
        (address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) =
            abi.decode(data, (address, address, uint256, uint256, uint8, bytes32, bytes32));
        ERC20(token).permit(owner, spender, value, deadline, v, r, s);
    }

    function _permitBatch(bytes[] calldata permitData) internal {
        for (uint256 i = 0; i < permitData.length; i++) {
            _permit(permitData[i]);
        }
    }
}
