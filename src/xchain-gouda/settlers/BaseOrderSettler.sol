// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {console} from "forge-std/console.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SettlementEvents} from "../base/SettlementEvents.sol";
import {IOrderSettler} from "../interfaces/IOrderSettler.sol";
import {ISettlementOracle} from "../interfaces/ISettlementOracle.sol";
import {
    ResolvedOrder,
    SettlementInfo,
    ActiveSettlement,
    OutputToken,
    SettlementStatus
} from "../base/SettlementStructs.sol";
import {SignedOrder, InputToken} from "../../base/ReactorStructs.sol";
import {ResolvedOrderLib} from "../lib/ResolvedOrderLib.sol";

/// @notice Generic cross-chain settler logic for settling off-chain signed orders
/// using arbitrary fill methods specified by a taker
abstract contract BaseOrderSettler is IOrderSettler, SettlementEvents {
    using SafeTransferLib for ERC20;
    using ResolvedOrderLib for ResolvedOrder;

    ISignatureTransfer public immutable permit2;

    mapping(bytes32 => ActiveSettlement) settlements;

    constructor(address _permit2) {
        permit2 = ISignatureTransfer(_permit2);
    }

    function getSettlement(bytes32 orderHash) external view returns (ActiveSettlement memory) {
        return settlements[orderHash];
    }

    /// @inheritdoc IOrderSettler
    function initiate(SignedOrder calldata order, address targetChainFiller) public override {
        _initiate(resolve(order), targetChainFiller);
    }

    /// @inheritdoc IOrderSettler
    function initiateBatch(SignedOrder[] calldata orders, address targetChainFiller)
        external
        override
        returns (uint8[] memory failed)
    {
        failed = new uint8[](orders.length);
        unchecked {
            for (uint256 i = 0; i < orders.length; i++) {
                (bool success,) = address(this).delegatecall(
                    abi.encodeWithSelector(IOrderSettler.initiate.selector, orders[i], targetChainFiller)
                );
                if (!success) failed[i] = 1;
            }
        }
    }

    function _initiate(ResolvedOrder memory order, address targetChainFiller) internal {
        order.validate(msg.sender);
        collectEscrowTokens(order);

        if (settlements[order.hash].optimisticDeadline != 0) revert SettlementAlreadyInitiated(order.hash);

        uint32 fillDeadline = uint32(block.timestamp) + order.info.fillPeriod;
        uint32 optimisticDeadline = uint32(block.timestamp) + order.info.optimisticSettlementPeriod;
        uint32 challengeDeadline = uint32(block.timestamp) + order.info.challengePeriod;

        ActiveSettlement storage settlement = settlements[order.hash];
        settlement.status = SettlementStatus.Pending;
        settlement.offerer = order.info.offerer;
        settlement.originChainFiller = msg.sender;
        settlement.targetChainFiller = targetChainFiller;
        settlement.settlementOracle = order.info.settlementOracle;
        settlement.fillDeadline = fillDeadline;
        settlement.optimisticDeadline = optimisticDeadline;
        settlement.challengeDeadline = challengeDeadline;
        settlement.input = order.input;
        settlement.fillerCollateral = order.fillerCollateral;
        settlement.challengerCollateral = order.challengerCollateral;
        settlement.outputs = keccak256(abi.encode(order.outputs));

        emit InitiateSettlement(
            order.hash,
            order.info.offerer,
            msg.sender,
            targetChainFiller,
            order.info.settlementOracle,
            fillDeadline,
            optimisticDeadline,
            challengeDeadline
            );
    }

    /// @inheritdoc IOrderSettler
    function cancel(bytes32 orderId) external override {
        ActiveSettlement memory settlement = settlements[orderId];

        verifySettlementInProgress(settlement, orderId);
        if (settlement.challengeDeadline >= block.timestamp) revert CannotCancelBeforeDeadline(orderId);

        settlements[orderId].status = SettlementStatus.Cancelled;

        ERC20(settlement.input.token).safeTransfer(settlement.offerer, settlement.input.amount);
        if (settlement.challenger != address(0)) {
            uint256 halfFillerCollateral = settlement.fillerCollateral.amount / 2;
            ERC20(settlement.fillerCollateral.token).safeTransfer(settlement.offerer, halfFillerCollateral);
            ERC20(settlement.fillerCollateral.token).safeTransfer(settlement.challenger, halfFillerCollateral);
            ERC20(settlement.challengerCollateral.token).safeTransfer(
                settlement.challenger, settlement.challengerCollateral.amount
            );
        } else {
            ERC20(settlement.fillerCollateral.token).safeTransfer(
                settlement.offerer, settlement.fillerCollateral.amount
            );
        }

        emit CancelSettlement(orderId);
    }

    function cancelBatch(bytes32[] calldata orderIds) external returns (uint8[] memory failed) {
        failed = new uint8[](orderIds.length);

        unchecked {
            for (uint256 i = 0; i < orderIds.length; i++) {
                (bool success,) =
                    address(this).delegatecall(abi.encodeWithSelector(IOrderSettler.cancel.selector, orderIds[i]));
                if (!success) failed[i] = 1;
            }
        }
    }

    /// @inheritdoc IOrderSettler
    function finalizeOptimistically(bytes32 orderId) external override {
        ActiveSettlement memory settlement = settlements[orderId];
        verifySettlementInProgress(settlement, orderId);

        if (settlement.status != SettlementStatus.Pending) revert CannotFinalizeChallengedSettlement(orderId);
        if (block.timestamp < settlement.optimisticDeadline) revert CannotFinalizeBeforeDeadline(orderId);

        settlements[orderId].status = SettlementStatus.Success;
        compensateFiller(orderId, settlement);
    }

    function finalize(bytes32 orderId, address filler, uint256 fillTimestamp, bytes32 outputs) external override {
        ActiveSettlement memory settlement = settlements[orderId];
        verifySettlementInProgress(settlement, orderId);

        if (msg.sender != settlement.settlementOracle) revert OnlyOracleCanFinalizeSettlement(orderId);
        if (fillTimestamp > settlement.fillDeadline) revert OrderFillExceededDeadline();
        if (outputs != settlement.outputs) revert InvalidOutputs(orderId);

        settlements[orderId].status = SettlementStatus.Success;
        ERC20(settlement.challengerCollateral.token).safeTransfer(
            settlement.originChainFiller, settlement.challengerCollateral.amount
        );
        compensateFiller(orderId, settlement);
    }

    function challengeSettlement(bytes32 orderId) external {
        ActiveSettlement memory settlement = settlements[orderId];
        if (settlement.optimisticDeadline == 0) revert SettlementDoesNotExist(orderId);
        if (settlement.status != SettlementStatus.Pending) revert CanOnlyChallengePendingSettlements(orderId);

        settlements[orderId].status = SettlementStatus.Challenged;
        settlements[orderId].challenger = msg.sender;
        collectChallengeBond(settlement);
        emit SettlementChallenged(orderId, msg.sender);
    }

    function compensateFiller(bytes32 orderId, ActiveSettlement memory settlement) internal {
        settlements[orderId].status = SettlementStatus.Success;
        ERC20(settlement.input.token).safeTransfer(settlement.originChainFiller, settlement.input.amount);
        ERC20(settlement.fillerCollateral.token).safeTransfer(
            settlement.originChainFiller, settlement.fillerCollateral.amount
        );
        emit FinalizeSettlement(orderId);
    }

    function verifySettlementInProgress(ActiveSettlement memory settlement, bytes32 orderId) internal pure {
        if (settlement.optimisticDeadline == 0) revert SettlementDoesNotExist(orderId);
        if (settlement.status > SettlementStatus.Challenged) revert SettlementAlreadyCompleted(orderId);
    }

    /// @notice Resolve order-type specific requirements into a generic order with the final inputs and outputs.
    /// @param order The encoded order to resolve
    /// @return resolvedOrder generic resolved order of inputs and outputs
    /// @dev should revert on any order-type-specific validation errors
    function resolve(SignedOrder calldata order) internal view virtual returns (ResolvedOrder memory resolvedOrder);

    /// @notice Collects swapper input tokens as well as collateral tokens of filler to escrow them until settlement is
    /// finalized or cancelled
    /// @param order The encoded order to transfer tokens for
    function collectEscrowTokens(ResolvedOrder memory order) internal virtual;

    /// @notice Collects swapper input tokens as well as collateral tokens of filler to escrow them until settlement is
    /// finalized or cancelled
    /// @param settlement The current information associated with the active settlement
    function collectChallengeBond(ActiveSettlement memory settlement) internal virtual;
}
