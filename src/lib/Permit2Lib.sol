// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {ResolvedOrder, ResolvedRelayOrder} from "../base/ReactorStructs.sol";

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

    /// @notice returns a ResolvedOrder into a permit object
    function toPermit(ResolvedRelayOrder memory order)
        internal
        pure
        returns (ISignatureTransfer.PermitBatchTransferFrom memory)
    {
        ISignatureTransfer.TokenPermissions[] memory permissions =
            new ISignatureTransfer.TokenPermissions[](order.inputs.length);
        for (uint256 i = 0; i < order.inputs.length; i++) {
            permissions[i] = ISignatureTransfer.TokenPermissions({
                token: address(order.inputs[i].token),
                amount: order.inputs[i].amount
            });
        }
        return ISignatureTransfer.PermitBatchTransferFrom({
            permitted: permissions,
            nonce: order.info.nonce,
            deadline: order.info.deadline
        });
    }

    /// @notice returns a ResolvedOrder into a permit object
    function transferDetails(ResolvedRelayOrder memory order)
        internal
        view
        returns (ISignatureTransfer.SignatureTransferDetails[] memory)
    {
        ISignatureTransfer.SignatureTransferDetails[] memory details =
            new ISignatureTransfer.SignatureTransferDetails[](order.inputs.length);
        for (uint256 i = 0; i < order.inputs.length; i++) {
            // if recipient is 0x0, use msg.sender
            address recipient = order.inputs[i].recipient == address(0) ? msg.sender : order.inputs[i].recipient;
            details[i] =
                ISignatureTransfer.SignatureTransferDetails({to: recipient, requestedAmount: order.inputs[i].amount});
        }
        return details;
    }
}
