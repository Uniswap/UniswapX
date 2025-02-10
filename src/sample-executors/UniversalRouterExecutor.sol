// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Owned} from "solmate/src/auth/Owned.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {IReactorCallback} from "../interfaces/IReactorCallback.sol";
import {IReactor} from "../interfaces/IReactor.sol";
import {CurrencyLibrary} from "../lib/CurrencyLibrary.sol";
import {ResolvedOrder, SignedOrder} from "../base/ReactorStructs.sol";

/// @notice A fill contract that uses UniversalRouter to execute trades
contract UniversalRouterExecutor is IReactorCallback, Owned {
    using SafeTransferLib for ERC20;
    using CurrencyLibrary for address;

    /// @notice thrown if reactorCallback is called with a non-whitelisted filler
    error CallerNotWhitelisted();
    /// @notice thrown if reactorCallback is called by an address other than the reactor
    error MsgSenderNotReactor();

    address public immutable universalRouter;
    mapping(address => bool) whitelistedCallers;
    IReactor public immutable reactor;
    IPermit2 public immutable permit2;

    modifier onlyWhitelistedCaller() {
        if (whitelistedCallers[msg.sender] == false) {
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

    constructor(
        address[] memory _whitelistedCallers,
        IReactor _reactor,
        address _owner,
        address _universalRouter,
        IPermit2 _permit2
    ) Owned(_owner) {
        for (uint256 i = 0; i < _whitelistedCallers.length; i++) {
            whitelistedCallers[_whitelistedCallers[i]] = true;
        }
        reactor = _reactor;
        universalRouter = _universalRouter;
        permit2 = _permit2;
    }

    /// @notice assume that we already have all output tokens
    function execute(SignedOrder calldata order, bytes calldata callbackData) external onlyWhitelistedCaller {
        reactor.executeWithCallback(order, callbackData);
    }

    /// @notice assume that we already have all output tokens
    function executeBatch(SignedOrder[] calldata orders, bytes calldata callbackData) external onlyWhitelistedCaller {
        reactor.executeBatchWithCallback(orders, callbackData);
    }

    /// @notice fill UniswapX orders using UniversalRouter
    /// @param callbackData It has the below encoded:
    /// address[] memory tokensToApproveForUniversalRouter: Max approve these tokens to universalRouter
    /// address[] memory tokensToApproveForReactor: Max approve these tokens to reactor
    /// bytes[] memory data: execution data
    function reactorCallback(ResolvedOrder[] calldata, bytes calldata callbackData) external onlyReactor {
        (
            address[] memory tokensToApproveForUniversalRouter,
            address[] memory tokensToApproveForReactor,
            bytes memory data
        ) = abi.decode(callbackData, (address[], address[], bytes));

        unchecked {
            for (uint256 i = 0; i < tokensToApproveForUniversalRouter.length; i++) {
                // Max approve token to permit2
                ERC20(tokensToApproveForUniversalRouter[i]).safeApprove(address(permit2), type(uint256).max);
                // Max approve token to universalRouter via permit2
                permit2.approve(
                    tokensToApproveForUniversalRouter[i], address(universalRouter), type(uint160).max, type(uint48).max
                );
            }

            for (uint256 i = 0; i < tokensToApproveForReactor.length; i++) {
                ERC20(tokensToApproveForReactor[i]).safeApprove(address(reactor), type(uint256).max);
            }
        }

        (bool success, bytes memory returnData) = universalRouter.call(data);
        if (!success) {
            assembly {
                revert(add(returnData, 32), mload(returnData))
            }
        }

        // transfer any native balance to the reactor
        // it will refund any excess
        if (address(this).balance > 0) {
            CurrencyLibrary.transferNative(address(reactor), address(this).balance);
        }
    }

    /// @notice Transfer all ETH in this contract to the recipient. Can only be called by owner.
    /// @param recipient The recipient of the ETH
    function withdrawETH(address recipient) external onlyOwner {
        SafeTransferLib.safeTransferETH(recipient, address(this).balance);
    }

    /// @notice Transfer the entire balance of an ERC20 token in this contract to a recipient. Can only be called by owner.
    /// @param token The ERC20 token to withdraw
    /// @param to The recipient of the tokens
    function withdrawERC20(ERC20 token, address to) external onlyOwner {
        token.safeTransfer(to, token.balanceOf(address(this)));
    }

    /// @notice Necessary for this contract to receive ETH when calling unwrapWETH()
    receive() external payable {}
}
