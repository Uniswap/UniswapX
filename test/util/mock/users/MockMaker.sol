// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {ERC20} from "solmate/tokens/ERC20.sol";

contract MockMaker {
    function approve(address token, address to, uint256 amount) external {
        ERC20(token).approve(to, amount);
    }
}
