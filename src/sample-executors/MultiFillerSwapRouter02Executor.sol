// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.19;

import {Owned} from "solmate/src/auth/Owned.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {WETH} from "solmate/src/tokens/WETH.sol";
import {IReactorCallback} from "../interfaces/IReactorCallback.sol";
import {CurrencyLibrary} from "../lib/CurrencyLibrary.sol";
import {ResolvedOrder, OutputToken} from "../base/ReactorStructs.sol";
import {ISwapRouter02} from "../external/ISwapRouter02.sol";

contract WhitelistedFillerStorage {
    address private immutable f1;
    address private immutable f2;
    address private immutable f3;
    address private immutable f4;
    address private immutable f5;
    address private immutable f6;
    address private immutable f7;
    address private immutable f8;
    address private immutable f9;
    address private immutable f10;

    constructor(address[10] memory _fillers) {
        require(_fillers.length <= 10, "Too many fillers");
        require(_fillers.length > 0, "No fillers");
        // assign fillers to their respective storage slots
        f1 = _fillers[0];
        f2 = _fillers[1];
        f3 = _fillers[2];
        f4 = _fillers[3];
        f5 = _fillers[4];
        f6 = _fillers[5];
        f7 = _fillers[6];
        f8 = _fillers[7];
        f9 = _fillers[8];
        f10 = _fillers[9];
    }

    function isWhitelistedFiller(address caller) internal view returns (bool) {
        if (
            caller == f1 || caller == f2 || caller == f3 || caller == f4 || caller == f5 || caller == f6 || caller == f7
                || caller == f8 || caller == f9 || caller == f10
        ) {
            return true;
        }

        return false;
    }

    function isWhitelistedFillerBST(address caller) internal view returns (bool) {
        // binary search, addresses are sorted in descending order
        unchecked {
            if (f5 == caller) return true;
            if (f5 < caller) {
                if (f3 == caller) return true;
                if (f3 < caller) {
                    if (f2 == caller) return true;
                    if (f2 < caller) {
                        if (f1 == caller) return true;
                        if (f1 < caller) {
                            return false;
                        } else {
                            return f4 == caller;
                        }
                    } else {
                        if (f4 == caller) return true;
                        if (f4 < caller) {
                            return false;
                        } else {
                            return f2 == caller;
                        }
                    }
                } else {
                    if (f4 == caller) return true;
                    if (f4 < caller) {
                        if (f6 == caller) return true;
                        if (f6 < caller) {
                            return false;
                        } else {
                            return f3 == caller;
                        }
                    } else {
                        if (f3 == caller) return true;
                        if (f3 < caller) {
                            return false;
                        } else {
                            return f6 == caller;
                        }
                    }
                }
            } else {
                if (f7 == caller) return true;
                if (f7 < caller) {
                    if (f6 == caller) return true;
                    if (f6 < caller) {
                        if (f9 == caller) return true;
                        if (f9 < caller) {
                            return false;
                        } else {
                            return f8 == caller;
                        }
                    } else {
                        if (f8 == caller) return true;
                        if (f8 < caller) {
                            return false;
                        } else {
                            return f6 == caller;
                        }
                    }
                } else {
                    if (f8 == caller) return true;
                    if (f8 < caller) {
                        if (f10 == caller) return true;
                        if (f10 < caller) {
                            return false;
                        } else {
                            return f7 == caller;
                        }
                    } else {
                        if (f7 == caller) return true;
                        if (f7 < caller) {
                            return false;
                        } else {
                            return f10 == caller;
                        }
                    }
                }
            }
        }
    }
}

/// @notice A fill contract that uses SwapRouter02 to execute trades
/// @dev This is the same functionality as SwapRouter02Executor, but it allows the owner
///      to whitelist multiple fillers to execute trades.
contract MultiFillerSwapRouter02Executor is IReactorCallback, WhitelistedFillerStorage, Owned {
    using SafeTransferLib for ERC20;
    using CurrencyLibrary for address;

    error CallerNotWhitelisted();
    error MsgSenderNotReactor();
    error EtherSendFail();
    error InsufficientWETHBalance();

    ISwapRouter02 private immutable swapRouter02;
    address private immutable reactor;
    WETH private immutable weth;

    // @param _reactor The address of the reactor contract
    // @param _owner The owner of this contract
    // @param _swapRouter02 The address of the SwapRouter02 contract
    // This contract supports up to a maximum of 10 whitelisted fillers
    // the addresses MUST be set in descending order
    // if you want to set less than the maximum number of fillers, set the rest to 0x0
    constructor(address _reactor, address _owner, ISwapRouter02 _swapRouter02, address[10] memory _fillers)
        Owned(_owner)
        WhitelistedFillerStorage(_fillers)
    {
        reactor = _reactor;
        swapRouter02 = _swapRouter02;
        weth = WETH(payable(_swapRouter02.WETH9()));
    }

    /// @param resolvedOrders The orders to fill
    /// @param filler This filler must be `whitelistedCaller`
    /// @param fillData It has the below encoded:
    /// address[] memory tokensToApproveForSwapRouter02: Max approve these tokens to swapRouter02
    /// address[] memory tokensToApproveForReactor: Max approve these tokens to reactor
    /// bytes[] memory multicallData: Pass into swapRouter02.multicall()
    function reactorCallback(ResolvedOrder[] calldata resolvedOrders, address filler, bytes calldata fillData)
        external
    {
        if (msg.sender != reactor) {
            revert MsgSenderNotReactor();
        }
        if (!isWhitelistedFiller(filler)) {
            revert CallerNotWhitelisted();
        }

        (address[] memory tokensToApproveForSwapRouter02, bytes[] memory multicallData) =
            abi.decode(fillData, (address[], bytes[]));

        for (uint256 i = 0; i < tokensToApproveForSwapRouter02.length; i++) {
            ERC20(tokensToApproveForSwapRouter02[i]).safeApprove(address(swapRouter02), type(uint256).max);
        }

        swapRouter02.multicall(type(uint256).max, multicallData);

        for (uint256 i = 0; i < resolvedOrders.length; i++) {
            ResolvedOrder memory order = resolvedOrders[i];
            for (uint256 j = 0; j < order.outputs.length; j++) {
                OutputToken memory output = order.outputs[j];
                output.token.transfer(output.recipient, output.amount);
            }
        }
    }

    /// @notice This function can be used to convert ERC20s to ETH that remains in this contract
    /// @param tokensToApprove Max approve these tokens to swapRouter02
    /// @param multicallData Pass into swapRouter02.multicall()
    function multicall(address[] calldata tokensToApprove, bytes[] calldata multicallData) external onlyOwner {
        for (uint256 i = 0; i < tokensToApprove.length; i++) {
            ERC20(tokensToApprove[i]).approve(address(swapRouter02), type(uint256).max);
        }
        swapRouter02.multicall(type(uint256).max, multicallData);
    }

    /// @notice Unwraps the contract's WETH9 balance and sends it to the recipient as ETH. Can only be called by owner.
    /// @param recipient The address receiving ETH
    function unwrapWETH(address recipient) external onlyOwner {
        uint256 balanceWETH = weth.balanceOf(address(this));

        if (balanceWETH == 0) revert InsufficientWETHBalance();

        weth.withdraw(balanceWETH);
        SafeTransferLib.safeTransferETH(recipient, address(this).balance);
    }

    /// @notice Transfer all ETH in this contract to the recipient. Can only be called by owner.
    /// @param recipient The recipient of the ETH
    function withdrawETH(address recipient) external onlyOwner {
        SafeTransferLib.safeTransferETH(recipient, address(this).balance);
    }

    receive() external payable {}
}
