// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {Owned} from "solmate/src/auth/Owned.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {IReactor} from "../interfaces/IReactor.sol";
import {CurrencyLibrary} from "../lib/CurrencyLibrary.sol";
import {SignedOrder} from "../base/ReactorStructs.sol";

/// @notice A simple fill contract that relays 2612 style permits on chain before filling a Relay order
contract PermitExecutor is Owned {
    using SafeTransferLib for ERC20;
    using CurrencyLibrary for address;

    /// @notice thrown if this contract is called by an address other than the whitelisted caller
    error CallerNotWhitelisted();

    address private immutable whitelistedCaller;
    IReactor private immutable reactor;

    modifier onlyWhitelistedCaller() {
        if (msg.sender != whitelistedCaller) {
            revert CallerNotWhitelisted();
        }
        _;
    }

    constructor(address _whitelistedCaller, IReactor _reactor, address _owner) Owned(_owner) {
        whitelistedCaller = _whitelistedCaller;
        reactor = _reactor;
    }

    /// @notice the reactor performs no verification that the user's signed permit is executed correctly
    ///         e.g. if the necessary approvals are already set, a filler can call this function or the standard execute function to fill the order
    /// @dev assume 2612 permit is collected offchain
    function executeWithPermit(SignedOrder calldata order, bytes calldata permitData) external onlyWhitelistedCaller {
        _permit(permitData);
        reactor.execute(order);
    }

    /// @notice assume that we already have all output tokens
    /// @dev assume 2612 permits are collected offchain
    function executeBatchWithPermit(SignedOrder[] calldata orders, bytes[] calldata permitData)
        external
        onlyWhitelistedCaller
    {
        _permitBatch(permitData);
        reactor.executeBatch(orders);
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

    /// @notice Transfer all tokens in this contract to the recipient. Can only be called by owner.
    /// @param tokens The tokens to withdraw
    /// @param recipient The recipient of the tokens
    function withdrawERC20(ERC20[] calldata tokens, address recipient) external onlyOwner {
        for (uint256 i = 0; i < tokens.length; i++) {
            ERC20 token = tokens[i];
            token.safeTransfer(recipient, token.balanceOf(address(this)));
        }
    }

    /// @notice Transfer all ETH in this contract to the recipient. Can only be called by owner.
    /// @param recipient The recipient of the ETH
    function withdrawETH(address recipient) external onlyOwner {
        SafeTransferLib.safeTransferETH(recipient, address(this).balance);
    }

    receive() external payable {}
}
