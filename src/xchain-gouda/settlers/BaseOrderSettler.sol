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
    SettlementStatus,
    SettlementKey,
    OutputToken,
    SettlementStage
} from "../base/SettlementStructs.sol";
import {SignedOrder, InputToken} from "../../base/ReactorStructs.sol";
import {ResolvedOrderLib} from "../lib/ResolvedOrderLib.sol";

/// @notice Generic cross-chain settler logic for settling off-chain signed orders
/// using arbitrary fill methods specified by a taker
abstract contract BaseOrderSettler is IOrderSettler, SettlementEvents {
    using SafeTransferLib for ERC20;
    using ResolvedOrderLib for ResolvedOrder;

    ISignatureTransfer public immutable permit2;

    mapping(bytes32 => SettlementStatus) settlements;

    constructor(address _permit2) {
        permit2 = ISignatureTransfer(_permit2);
    }

    function getSettlement(bytes32 orderId) external view returns (SettlementStatus memory) {
        return settlements[orderId];
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

        if (settlements[order.hash].key != 0) revert SettlementAlreadyInitiated(order.hash);

        uint32 fillDeadline = uint32(block.timestamp) + order.info.fillPeriod;
        uint32 optimisticDeadline = uint32(block.timestamp) + order.info.optimisticSettlementPeriod;
        uint32 challengeDeadline = uint32(block.timestamp) + order.info.challengePeriod;

        SettlementKey memory key = SettlementKey(
            order.info.offerer,
            msg.sender,
            targetChainFiller,
            order.info.settlementOracle,
            fillDeadline,
            optimisticDeadline,
            challengeDeadline,
            order.input,
            order.fillerCollateral,
            order.challengerCollateral,
            keccak256(abi.encode(order.outputs))
        );

        settlements[order.hash] = SettlementStatus(keccak256(abi.encode(key)), SettlementStage.Pending, address(0));

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
    function cancel(bytes32 orderId, SettlementKey calldata key) external override {
        SettlementStatus storage settlement = settlements[orderId];
        if (settlement.key != keccak256(abi.encode(key))) revert InvalidSettlementKey();
        if (settlement.status > SettlementStage.Challenged) revert SettlementAlreadyCompleted(orderId);
        if (key.challengeDeadline >= block.timestamp) revert CannotCancelBeforeDeadline(orderId);

        settlement.status = SettlementStage.Cancelled;

        ERC20(key.input.token).safeTransfer(key.offerer, key.input.amount);
        if (settlement.challenger != address(0)) {
            uint256 halfFillerCollateral = key.fillerCollateral.amount / 2;
            ERC20(key.fillerCollateral.token).safeTransfer(key.offerer, halfFillerCollateral);
            ERC20(key.fillerCollateral.token).safeTransfer(settlement.challenger, halfFillerCollateral);
            ERC20(key.challengerCollateral.token).safeTransfer(settlement.challenger, key.challengerCollateral.amount);
        } else {
            ERC20(key.fillerCollateral.token).safeTransfer(key.offerer, key.fillerCollateral.amount);
        }

        emit CancelSettlement(orderId);
    }

    function cancelBatch(bytes32[] calldata orderIds, SettlementKey[] calldata keys)
        external
        returns (uint8[] memory failed)
    {
        failed = new uint8[](orderIds.length);

        unchecked {
            for (uint256 i = 0; i < keys.length; i++) {
                (bool success,) = address(this).delegatecall(
                    abi.encodeWithSelector(IOrderSettler.cancel.selector, orderIds[i], keys[i])
                );
                if (!success) failed[i] = 1;
            }
        }
    }

    /// @inheritdoc IOrderSettler
    function finalizeOptimistically(bytes32 orderId, SettlementKey calldata key) external override {
        SettlementStatus storage settlement = settlements[orderId];
        if (settlement.key == 0) revert SettlementDoesNotExist(orderId);
        if (settlement.key != keccak256(abi.encode(key))) revert InvalidSettlementKey();
        if (settlement.status != SettlementStage.Pending) {
            revert OptimisticFinalizationForPendingSettlementsOnly(orderId);
        }
        if (block.timestamp < key.optimisticDeadline) revert CannotFinalizeBeforeDeadline(orderId);

        settlement.status = SettlementStage.Success;
        compensateFiller(orderId, key);
    }

    function finalize(bytes32 orderId, SettlementKey calldata key, uint256 fillTimestamp) external override {
        SettlementStatus storage settlement = settlements[orderId];
        checkValidSettlement(key, settlement, orderId);
        if (settlement.status > SettlementStage.Challenged) revert SettlementAlreadyCompleted(orderId);

        if (msg.sender != key.settlementOracle) revert OnlyOracleCanFinalizeSettlement(orderId);
        if (fillTimestamp > key.fillDeadline) revert OrderFillExceededDeadline();

        settlement.status = SettlementStage.Success;
        ERC20(key.challengerCollateral.token).safeTransfer(key.originChainFiller, key.challengerCollateral.amount);
        compensateFiller(orderId, key);
    }

    function challengeSettlement(bytes32 orderId, SettlementKey calldata key) external {
        SettlementStatus storage settlement = settlements[orderId];
        checkValidSettlement(key, settlement, orderId);
        if (settlement.status != SettlementStage.Pending) revert CanOnlyChallengePendingSettlements(orderId);

        settlement.status = SettlementStage.Challenged;
        settlement.challenger = msg.sender;
        collectChallengeBond(key);
        emit SettlementChallenged(orderId, msg.sender);
    }

    function compensateFiller(bytes32 orderId, SettlementKey calldata key) internal {
        ERC20(key.input.token).safeTransfer(key.originChainFiller, key.input.amount);
        ERC20(key.fillerCollateral.token).safeTransfer(key.originChainFiller, key.fillerCollateral.amount);
        emit FinalizeSettlement(orderId);
    }

    function checkValidSettlement(SettlementKey calldata key, SettlementStatus storage settlement, bytes32 orderId)
        internal
        view
    {
        if (settlement.key == 0) revert SettlementDoesNotExist(orderId);
        if (settlement.key != keccak256(abi.encode(key))) revert InvalidSettlementKey();
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
    /// @param key The current information associated with the active settlement
    function collectChallengeBond(SettlementKey calldata key) internal virtual;
}
