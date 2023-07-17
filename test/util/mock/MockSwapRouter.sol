// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {Path} from "../lib/Path.sol";
import {ISwapRouter02, ExactInputParams} from "../../../src/external/ISwapRouter02.sol";

contract MockSwapRouter {
    using SafeTransferLib for ERC20;
    using Path for bytes;

    uint256 public constant SWAP_RATE_GRANULARITY = 10000;
    uint256 public swapRate = 10000; // start with swap at 1 for 1
    address public immutable WETH9;

    constructor(address wethAddress) {
        WETH9 = wethAddress;
    }

    function setSwapRate(uint256 newRate) public {
        swapRate = newRate;
    }

    function exactInput(ExactInputParams calldata params) external returns (uint256 amountOut) {
        bytes memory path = params.path;
        (address tokenIn,,) = path.decodeFirstPool();

        while (path.hasMultiplePools()) {
            path = path.skipToken();
        }
        (, address tokenOut,) = path.decodeFirstPool();

        amountOut = (params.amountIn * swapRate) / SWAP_RATE_GRANULARITY;
        require(amountOut >= params.amountOutMinimum, "Too little received");
        ERC20(tokenIn).safeTransferFrom(msg.sender, address(this), params.amountIn);
        ERC20(tokenOut).safeTransfer(params.recipient, amountOut);
    }

    function multicall(uint256, bytes[] calldata data) public payable returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            (bool success, bytes memory result) = address(this).delegatecall(data[i]);

            if (!success) {
                // Next 5 lines from https://ethereum.stackexchange.com/a/83577
                if (result.length < 68) revert();
                assembly {
                    result := add(result, 0x04)
                }
                revert(abi.decode(result, (string)));
            }

            results[i] = result;
        }
    }
}
