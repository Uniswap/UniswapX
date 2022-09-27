// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {TokenDetails, TokenType} from "permitpost/interfaces/IPermitPost.sol";

/// @notice handling some permitpost-specific encoding
library PermitPostLib {
    /// @notice returns a TokenDetails array of length 1 with the given token and amount
    function toTokenDetails(address token, uint256 amount) internal pure returns (TokenDetails[] memory result) {
        result = new TokenDetails[](1);
        result[0] = TokenDetails(TokenType.ERC20, address(token), amount, 0);
    }
}
