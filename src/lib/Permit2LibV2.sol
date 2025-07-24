// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {ResolvedOrderV2} from "../base/ReactorStructs.sol";

/// @notice handling some permit2-specific encoding for V2 structures
library Permit2LibV2 {
    /// @notice returns a ResolvedOrderV2 into a permit object
    function toPermit(ResolvedOrderV2 memory order)
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

    /// @notice returns a ResolvedOrderV2 into a permit object
    function transferDetails(ResolvedOrderV2 memory order, address to)
        internal
        pure
        returns (ISignatureTransfer.SignatureTransferDetails memory)
    {
        return ISignatureTransfer.SignatureTransferDetails({to: to, requestedAmount: order.input.amount});
    }
}