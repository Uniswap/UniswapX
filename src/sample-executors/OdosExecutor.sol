// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Owned} from "solmate/src/auth/Owned.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {WETH} from "solmate/src/tokens/WETH.sol";
import {IReactorCallback} from "../interfaces/IReactorCallback.sol";
import {IReactor} from "../interfaces/IReactor.sol";
import {CurrencyLibrary} from "../lib/CurrencyLibrary.sol";
import {ResolvedOrder, SignedOrder} from "../base/ReactorStructs.sol";

/// @notice A fill contract that uses Odos to execute trades
contract OdosExecutor is IReactorCallback, Owned {
    using SafeTransferLib for ERC20;
    using CurrencyLibrary for address;

    event OdosContractChanged(address newOdos, address oldOdos);
    event ReactorChanged(address newReactor, address oldReactor);

    /// @notice thrown if reactorCallback is called with a non-whitelisted filler
    error CallerNotWhitelisted();
    /// @notice thrown if reactorCallback is called by an address other than the reactor
    error MsgSenderNotReactor();
    error OdosCallFailed();

    address public odos;
    address private immutable whitelistedCaller;
    IReactor public reactor;
    WETH private immutable weth;

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

    constructor(address _whitelistedCaller, IReactor _reactor, address _owner, address _odos, address _weth)
        Owned(_owner)
    {
        whitelistedCaller = _whitelistedCaller;
        reactor = _reactor;
        odos = _odos;
        weth = WETH(payable(_weth));
    }

    /// @notice assume that we already have all output tokens
    function execute(SignedOrder calldata order, bytes calldata callbackData) external onlyWhitelistedCaller {
        reactor.executeWithCallback(order, callbackData);
    }

    /// @notice assume that we already have all output tokens
    function executeBatch(SignedOrder[] calldata orders, bytes calldata callbackData) external onlyWhitelistedCaller {
        reactor.executeBatchWithCallback(orders, callbackData);
    }

    /// @notice fill UniswapX orders using Odos
    /// @param callbackData It has the below encoded:
    /// address[] memory tokensToApproveForOdos: Max approve these tokens to Odos contract
    /// address[] memory tokensToApproveForReactor: Max approve these tokens to reactor
    /// bytes memory odosAssembly: low level call to Odos contract using transaction.data 
    function reactorCallback(ResolvedOrder[] calldata, bytes calldata callbackData) external onlyReactor {
        (
            address[] memory tokensToApproveForOdos,
            address[] memory tokensToApproveForReactor,
            bytes memory odosAssembly
        ) = abi.decode(callbackData, (address[], address[], bytes));

        unchecked {
            for (uint256 i = 0; i < tokensToApproveForOdos.length; i++) {
                ERC20(tokensToApproveForOdos[i]).safeApprove(address(odos), type(uint256).max);
            }

            for (uint256 i = 0; i < tokensToApproveForReactor.length; i++) {
                ERC20(tokensToApproveForReactor[i]).safeApprove(address(reactor), type(uint256).max);
            }
        }

        
        // perform low level call to odos with transaction.data set as odosAssembly using transaction.data
        (bool success, ) = odos.call(odosAssembly);
        if (!success) {
            revert OdosCallFailed();
        }




        // transfer any native balance to the reactor
        // it will refund any excess
        if (address(this).balance > 0) {
            CurrencyLibrary.transferNative(address(reactor), address(this).balance);
        }
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

    /// @notice Transfer the entire balance of an ERC20 token in this contract to a recipient. Can only be called by owner.
    /// @param token The ERC20 token to withdraw
    /// @param to The recipient of the tokens
    function withdrawERC20(ERC20 token, address to) external onlyOwner {
        token.safeTransfer(to, token.balanceOf(address(this)));
    }

    function withdrawERC20Batch(ERC20[] calldata tokens, address to) external onlyOwner {
        for (uint256 i = 0; i < tokens.length; i++) {
            tokens[i].safeTransfer(to, tokens[i].balanceOf(address(this)));
        }
    }

    /// @notice Update the reactor contract address. Can only be called by owner.
    /// @param _reactor The new reactor contract address
    function updateReactor(IReactor _reactor) external onlyOwner {
        emit ReactorChanged(address(_reactor), address(reactor));
        reactor = _reactor;
    }

    function updateOdos(address _odos) external onlyOwner {
        emit ReactorChanged(_odos, odos);
        odos = odos;
    }

    /// @notice Necessary for this contract to receive ETH when calling unwrapWETH()
    receive() external payable {}
}
