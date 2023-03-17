// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

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
import {OutputTokenLib} from "../lib/OutputTokenLib.sol";

/// @notice Generic cross-chain settler logic for settling off-chain signed orders
/// using arbitrary fill methods specified by a taker
abstract contract BaseOrderSettler is IOrderSettler, SettlementEvents {
    using SafeTransferLib for ERC20;
    using ResolvedOrderLib for ResolvedOrder;
    using OutputTokenLib for OutputToken[];

    ISignatureTransfer public immutable permit2;

    mapping(bytes32 => SettlementStatus) settlements;

    constructor(address _permit2) {
        permit2 = ISignatureTransfer(_permit2);
    }

    function getSettlement(bytes32 orderHash) external view returns (SettlementStatus memory) {
        return settlements[orderHash];
    }

    /// @inheritdoc IOrderSettler
    function initiate(SignedOrder calldata order) public override {
        _initiate(resolve(order));
    }

    /// @inheritdoc IOrderSettler
    function initiateBatch(SignedOrder[] calldata orders) external override returns (uint8[] memory failed) {
        failed = new uint8[](orders.length);
        unchecked {
            for (uint256 i = 0; i < orders.length; i++) {
                (bool success,) =
                    address(this).delegatecall(abi.encodeWithSelector(IOrderSettler.initiate.selector, orders[i]));
                if (!success) failed[i] = 1;
            }
        }
    }

    function _initiate(ResolvedOrder memory order) internal {
        order.validate(msg.sender);
        collectEscrowTokens(order);

        if (settlements[order.hash].keyHash != 0) revert SettlementAlreadyInitiated();

        SettlementKey memory key = SettlementKey(
            order.info.offerer,
            msg.sender,
            order.info.settlementOracle,
            uint32(block.timestamp) + order.info.fillPeriod,
            uint32(block.timestamp) + order.info.optimisticSettlementPeriod,
            uint32(block.timestamp) + order.info.challengePeriod,
            order.input,
            order.fillerCollateral,
            order.challengerCollateral,
            order.outputs.hash()
        );

        settlements[order.hash] = SettlementStatus(keccak256(abi.encode(key)), SettlementStage.Pending, address(0));

        emit InitiateSettlement(order.hash, key.offerer, key.filler);
    }

    /// @inheritdoc IOrderSettler
    function cancel(bytes32 orderHash, SettlementKey calldata key) external override {
        SettlementStatus storage settlementStatus = settlements[orderHash];
        if (settlementStatus.keyHash != keccak256(abi.encode(key))) revert InvalidSettlementKey();
        if (settlementStatus.status > SettlementStage.Challenged) revert SettlementAlreadyCompleted();
        if (block.timestamp <= key.challengeDeadline) revert CannotCancelBeforeDeadline();

        settlementStatus.status = SettlementStage.Cancelled;

        ERC20(key.input.token).safeTransfer(key.offerer, key.input.amount);
        if (settlementStatus.challenger != address(0)) {
            uint256 halfFillerCollateral = key.fillerCollateral.amount / 2;
            ERC20(key.fillerCollateral.token).safeTransfer(key.offerer, halfFillerCollateral);
            ERC20(key.fillerCollateral.token).safeTransfer(settlementStatus.challenger, halfFillerCollateral);
            ERC20(key.challengerCollateral.token).safeTransfer(
                settlementStatus.challenger, key.challengerCollateral.amount
            );
        } else {
            ERC20(key.fillerCollateral.token).safeTransfer(key.offerer, key.fillerCollateral.amount);
        }

        emit CancelSettlement(orderHash);
    }

    function cancelBatch(bytes32[] calldata orderHashes, SettlementKey[] calldata keys)
        external
        returns (uint8[] memory failed)
    {
        failed = new uint8[](orderHashes.length);

        unchecked {
            for (uint256 i = 0; i < keys.length; i++) {
                (bool success,) = address(this).delegatecall(
                    abi.encodeWithSelector(IOrderSettler.cancel.selector, orderHashes[i], keys[i])
                );
                if (!success) failed[i] = 1;
            }
        }
    }

    /// @inheritdoc IOrderSettler
    function finalizeOptimistically(bytes32 orderHash, SettlementKey calldata key) external override {
        SettlementStatus storage settlementStatus = settlements[orderHash];
        checkValidSettlement(key, settlementStatus);
        if (settlementStatus.status != SettlementStage.Pending) {
            revert OptimisticFinalizationForPendingSettlementsOnly();
        }
        if (block.timestamp < key.optimisticDeadline) revert CannotFinalizeBeforeDeadline();

        settlementStatus.status = SettlementStage.Success;
        compensateFiller(orderHash, key);
    }

    function finalize(bytes32 orderHash, SettlementKey calldata key, uint256 fillTimestamp) external override {
        SettlementStatus storage settlementStatus = settlements[orderHash];
        checkValidSettlement(key, settlementStatus);

        if (msg.sender != key.settlementOracle) revert OnlyOracleCanFinalizeSettlement();
        if (settlementStatus.status > SettlementStage.Challenged) revert SettlementAlreadyCompleted();
        if (fillTimestamp > key.fillDeadline) revert OrderFillExceededDeadline();

        settlementStatus.status = SettlementStage.Success;
        ERC20(key.challengerCollateral.token).safeTransfer(key.filler, key.challengerCollateral.amount);
        compensateFiller(orderHash, key);
    }

    function challengeSettlement(bytes32 orderHash, SettlementKey calldata key) external {
        SettlementStatus storage settlementStatus = settlements[orderHash];
        checkValidSettlement(key, settlementStatus);
        if (settlementStatus.status != SettlementStage.Pending) revert ChallengePendingSettlementsOnly();
        if (block.timestamp > key.challengeDeadline) revert ChallengeDeadlinePassed();

        settlementStatus.status = SettlementStage.Challenged;
        settlementStatus.challenger = msg.sender;
        collectChallengeBond(key);
        emit SettlementChallenged(orderHash, msg.sender);
    }

    function compensateFiller(bytes32 orderHash, SettlementKey calldata key) internal {
        ERC20(key.input.token).safeTransfer(key.filler, key.input.amount);
        ERC20(key.fillerCollateral.token).safeTransfer(key.filler, key.fillerCollateral.amount);
        emit FinalizeSettlement(orderHash);
    }

    function checkValidSettlement(SettlementKey calldata key, SettlementStatus storage settlementStatus)
        internal
        view
    {
        if (settlementStatus.keyHash == 0) revert SettlementDoesNotExist();
        if (settlementStatus.keyHash != keccak256(abi.encode(key))) revert InvalidSettlementKey();
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
