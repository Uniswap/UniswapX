// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ERC20} from "solmate/src/tokens/ERC20.sol";

/// @notice ERC20 mock that mimics USDT-style approve semantics.
/// @dev Reverts when changing non-zero allowance to another non-zero allowance.
contract MockUSDTApproveToken is ERC20 {
    error NonZeroToNonZeroApprove();

    constructor(string memory name, string memory symbol, uint8 decimals) ERC20(name, symbol, decimals) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        if (amount != 0 && allowance[msg.sender][spender] != 0) {
            revert NonZeroToNonZeroApprove();
        }
        return super.approve(spender, amount);
    }
}
