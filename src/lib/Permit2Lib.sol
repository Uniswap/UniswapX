// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {ResolvedOrder} from "../base/ReactorStructs.sol";

/// @notice handling some permit2-specific encoding
library Permit2Lib {
    /// @notice returns a ResolvedOrder into a permit object
    function toPermit(ResolvedOrder memory order)
        internal
        pure
        returns (ISignatureTransfer.PermitTransferFrom memory)
    {
        return ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({
                token: address(order.input.token),
                amount: order.input.maxAmount
            }),
            nonce: order.info.nonce,
            deadline: order.info.deadline
        });
    }

    /// @notice returns a ResolvedOrder into a permit object
    function transferDetails(ResolvedOrder memory order, address to)
        internal
        pure
        returns (ISignatureTransfer.SignatureTransferDetails memory)
    {
        return ISignatureTransfer.SignatureTransferDetails({to: to, requestedAmount: order.input.amount});
    }
}
