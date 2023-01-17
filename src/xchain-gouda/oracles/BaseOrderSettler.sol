// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SettlementEvents} from "../base/SettlementEvents.sol";
import {IOrderSettler} from "../interfaces/IOrderSettler.sol";
import {ISettlementOracle, SettlementFillInfo} from "../interfaces/ISettlementOracle.sol";
import {ResolvedOrder, SettlementInfo, OutputToken, OrderStatus} from "../base/SettlementStructs.sol";
import {SignedOrder, InputToken} from "../../base/ReactorStructs.sol";
import {ResolvedOrderLib} from "../lib/ResolvedOrderLib.sol";

/// @notice Generic cross-chain reactor logic for settling off-chain signed orders
///     using arbitrary fill methods specified by a taker
abstract contract BaseOrderSettler is IOrderSettler, SettlementEvents {
    using SafeTransferLib for ERC20;
    using ResolvedOrderLib for ResolvedOrder;

    ISignatureTransfer public immutable permit2;

    mapping(bytes32 => ResolvedOrder) settlements;

    constructor(address _permit2) {
        permit2 = ISignatureTransfer(_permit2);
    }

    /// @inheritdoc IOrderSettler
    function initiateSettlement(SignedOrder calldata order, address fillRecipient) external override {
        ResolvedOrder[] memory resolvedOrders = new ResolvedOrder[](1);
        resolvedOrders[0] = resolve(order, fillRecipient);
        _initiateEscrow(resolvedOrders);
    }

    function _initiateEscrow(ResolvedOrder[] memory orders) internal {
        unchecked {
            for (uint256 i = 0; i < orders.length; i++) {
                ResolvedOrder memory order = orders[i];
                order.validate(msg.sender);
                transferEscrowTokens(order);
                settlements[order.hash] = order;
                emit InitiateSettlement(
                    order.hash, msg.sender, order.info.crossChainListener, order.info.nonce, order.settlementDeadline
                    );
            }
        }
    }

    /// @inheritdoc IOrderSettler
    function cancelSettlement(bytes32 settlementId) external override {
        ResolvedOrder storage order = settlements[settlementId];
        if (order.status == OrderStatus.Pending && order.settlementDeadline > block.timestamp) {
            order.status = OrderStatus.Cancelled;
            ERC20(order.input.token).safeTransfer(order.info.offerer, order.input.amount);
            ERC20(order.collateral.token).safeTransfer(order.info.offerer, order.input.amount);
        }
    }

    /// @inheritdoc IOrderSettler
    function finalizeSettlement(bytes32 settlementId) external override {
        ResolvedOrder storage order = settlements[settlementId];
        if (order.status == OrderStatus.Pending && order.settlementDeadline <= block.timestamp) {
            SettlementFillInfo[] memory fillInfo =
                ISettlementOracle(order.info.crossChainListener).getSettlementFillInfo(settlementId);
            // somehow check that fillInfo array meets all the requirements of output tokens array
            // transfer collateral & swap escrow to filler
        }
    }

    /// @notice Resolve order-type specific requirements into a generic order with the final inputs and outputs.
    /// @param order The encoded order to resolve
    /// @return resolvedOrder generic resolved order of inputs and outputs
    /// @dev should revert on any order-type-specific validation errors
    function resolve(SignedOrder calldata order, address fillRecipient)
        internal
        view
        virtual
        returns (ResolvedOrder memory resolvedOrder);

    /// @notice Transfers swapper input tokens as well as collateral tokens of filler
    /// @param order The encoded order to transfer tokens for
    function transferEscrowTokens(ResolvedOrder memory order) internal virtual;
}
