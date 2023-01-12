// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {XReactorEvents} from "../base/XReactorEvents.sol";
import {IXReactor} from "../interfaces/IXReactor.sol";
import {ResolvedXOrder, XOrderInfo, XOutputToken} from "../base/XReactorStructs.sol";
import {SignedOrder, InputToken} from "../../base/ReactorStructs.sol";
import {ResolvedXOrderLib} from "../lib/ResolvedXOrderLib.sol";

/// @notice Generic cross-chain reactor logic for settling off-chain signed orders
///     using arbitrary fill methods specified by a taker
abstract contract BaseXReactor is IXReactor, XReactorEvents {
    using SafeTransferLib for ERC20;
    using ResolvedXOrderLib for ResolvedXOrder;

    ISignatureTransfer public immutable permit2;

    mapping(bytes32 => ResolvedXOrder) pendingSettlements;

    constructor(address _permit2) {
        permit2 = ISignatureTransfer(_permit2);
    }

    /// @inheritdoc IXReactor
    function initiateSettlement(SignedOrder calldata order, bytes calldata settlementData) external override {
        ResolvedXOrder[] memory resolvedOrders = new ResolvedXOrder[](1);
        resolvedOrders[0] = resolve(order);
        _initiateEscrow(resolvedOrders, settlementData);
    }

    /// @notice validates and fills a list of orders, marking it as filled
    function _initiateEscrow(ResolvedXOrder[] memory orders, bytes calldata settlementData) internal {
        unchecked {
            for (uint256 i = 0; i < orders.length; i++) {
                ResolvedXOrder memory order = orders[i];
                order.validate(msg.sender);
                transferEscrowTokens(order);
                pendingSettlements[order.hash] = order;
                emit InitiateSettlement(order.hash, msg.sender, order.info.settlementOracle, order.info.nonce);
            }
        }
    }

    /// @notice Resolve order-type specific requirements into a generic order with the final inputs and outputs.
    /// @param order The encoded order to resolve
    /// @return resolvedOrder generic resolved order of inputs and outputs
    /// @dev should revert on any order-type-specific validation errors
    function resolve(SignedOrder calldata order) internal view virtual returns (ResolvedXOrder memory resolvedOrder);

    /// @notice Transfers swapper input tokens as well as collateral tokens of filler
    /// @param order The encoded order to transfer tokens for
    function transferEscrowTokens(ResolvedXOrder memory order) internal virtual;
}
