// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {TokenAmount} from "./ReactorStructs.sol";

struct Signature {
    uint8 v;
    bytes32 r;
    bytes32 s;
}

/// @notice Contract to manage user ERC20 approvals
/// @dev Transfers tokens on behalf of a user via signed permit
interface IPermitPost {
    /// @notice Transfer tokens using a signed permit message
    function transferFrom(
        TokenAmount[] memory tokens,
        address from,
        address to,
        bytes32 salt,
        Signature calldata sig
    )
        external;
}
