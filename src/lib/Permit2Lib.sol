// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ISignatureTransfer} from "permit2/interfaces/ISignatureTransfer.sol";
import {ResolvedOrder} from "../base/ReactorStructs.sol";

/// @notice handling some permit2-specific encoding
library Permit2Lib {
    /// @notice returns a ResolvedOrder into a permit object
    function toPermit(ResolvedOrder memory order)
        internal
        view
        returns (ISignatureTransfer.PermitTransferFrom memory)
    {
        return ISignatureTransfer.PermitTransferFrom({
            token: order.input.token,
            spender: address(this),
            signedAmount: order.input.amount,
            nonce: order.info.nonce,
            deadline: order.info.deadline
        });
    }
}
