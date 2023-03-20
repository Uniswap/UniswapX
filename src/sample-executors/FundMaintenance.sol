// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {Owned} from "solmate/src/auth/Owned.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {WETH} from "solmate/src/tokens/WETH.sol";
import {ISwapRouter02} from "../external/ISwapRouter02.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import "forge-std/console2.sol";

abstract contract FundMaintenance is Owned {
    using SafeTransferLib for ERC20;

    error InsufficientWETHBalance();

    WETH private immutable WETH9;
    ISwapRouter02 public immutable SWAP_ROUTER_02;

    constructor(address _swapRouter02, address _owner) Owned(_owner) {
        SWAP_ROUTER_02 = ISwapRouter02(_swapRouter02);
        WETH9 = WETH(payable(SWAP_ROUTER_02.WETH9()));
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

    /// @notice This function can be used to convert ERC20s to ETH that remains in this contract
    /// @param tokensToApprove Max approve these tokens to swapRouter02
    /// @param multicallData Pass into swapRouter02.multicall()
    function swapMulticall(address[] calldata tokensToApprove, bytes[] calldata multicallData) external onlyOwner {
        for (uint256 i = 0; i < tokensToApprove.length; i++) {
            ERC20(tokensToApprove[i]).approve(address(SWAP_ROUTER_02), type(uint256).max);
        }
        SWAP_ROUTER_02.multicall(type(uint256).max, multicallData);
    }

    receive() external payable {}
}
