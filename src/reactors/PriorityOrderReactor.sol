// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {BaseReactor} from "./BaseReactor.sol";
import {Permit2Lib} from "../lib/Permit2Lib.sol";
import {PriorityOrderLib, PriorityOrder, PriorityInput, PriorityOutput} from "../lib/PriorityOrderLib.sol";
import {PriorityFeeLib} from "../lib/PriorityFeeLib.sol";
import {SignedOrder, ResolvedOrder} from "../base/ReactorStructs.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";

/// @notice Reactor for priority orders
/// @dev only supported on chains which use priority fee transaction ordering
contract PriorityOrderReactor is BaseReactor {
    using Permit2Lib for ResolvedOrder;
    using PriorityOrderLib for PriorityOrder;
    using PriorityFeeLib for PriorityInput;
    using PriorityFeeLib for PriorityOutput[];

    /// @notice thrown when an order's deadline is in the past
    error InvalidDeadline();
    /// @notice thrown when an order's auctionStartBlock is in the future
    error OrderNotFillable();
    /// @notice thrown when an order's input and outputs both scale with priority fee
    error InputOutputScaling();
    /// @notice thrown when an order's cosignature does not match the expected cosigner
    error InvalidCosignature();
    /// @notice thrown when an order's cosigner target block is invalid
    error InvalidCosignerTargetBlock();
    /// @notice thrown when an order's min priority fee is greater than the priority fee of the transaction
    error InsufficientPriorityFee();

    constructor(IPermit2 _permit2, address _protocolFeeOwner) BaseReactor(_permit2, _protocolFeeOwner) {}

    /// @inheritdoc BaseReactor
    /// @notice tx.gasprice must be greater than or equal to block.basefee
    function _resolve(SignedOrder calldata signedOrder)
        internal
        view
        override
        returns (ResolvedOrder memory resolvedOrder)
    {
        PriorityOrder memory order = abi.decode(signedOrder.order, (PriorityOrder));
        bytes32 orderHash = order.hash();

        _updateWithCosignerData(order);
        _validateOrder(orderHash, order);

        uint256 priorityFee = tx.gasprice - block.basefee;
        if (priorityFee < order.minPriorityFeeWei) {
            revert InsufficientPriorityFee();
        }
        priorityFee -= order.minPriorityFeeWei;

        resolvedOrder = ResolvedOrder({
            info: order.info,
            input: order.input.scale(priorityFee),
            outputs: order.outputs.scale(priorityFee),
            sig: signedOrder.sig,
            hash: orderHash
        });
    }

    /// @inheritdoc BaseReactor
    function _transferInputTokens(ResolvedOrder memory order, address to) internal override {
        permit2.permitWitnessTransferFrom(
            order.toPermit(),
            order.transferDetails(to),
            order.info.swapper,
            order.hash,
            PriorityOrderLib.PERMIT2_ORDER_TYPE,
            order.sig
        );
    }

    /// @notice update the order with the cosigner's data
    function _updateWithCosignerData(PriorityOrder memory order) internal view {
        /// if there is a cosigned targetBlock, and we are not yet in the openAuction
        if (order.cosignerData.auctionTargetBlock != 0) {
            /// the cosigned target block must be before the openAuctionStartBlock
            if (order.cosignerData.auctionTargetBlock > order.openAuctionStartBlock) {
                revert InvalidCosignerTargetBlock();
            }
            /// if we are not yet in the openAuction, set the auctionStartBlock to the cosigned target block
            if (block.number < order.openAuctionStartBlock) {
                order.auctionStartBlock = order.cosignerData.auctionTargetBlock;
            }
        }
    }

    /// @notice validate the priority order fields
    /// - deadline must be in the future
    /// - auctionStartBlock must be in the past
    /// - if input scales with priority fee, outputs must not scale
    /// - order's cosigner must have signed over (orderHash || cosignerData)
    /// @dev Throws if the order is invalid
    function _validateOrder(bytes32 orderHash, PriorityOrder memory order) internal view {
        if (order.info.deadline < block.timestamp) {
            revert InvalidDeadline();
        }

        if (order.auctionStartBlock > block.number) {
            revert OrderNotFillable();
        }

        if (order.input.mpsPerPriorityFeeWei > 0) {
            for (uint256 i = 0; i < order.outputs.length; i++) {
                if (order.outputs[i].mpsPerPriorityFeeWei > 0) {
                    revert InputOutputScaling();
                }
            }
        }

        (bytes32 r, bytes32 s) = abi.decode(order.cosignature, (bytes32, bytes32));
        uint8 v = uint8(order.cosignature[64]);
        // cosigner signs over (orderHash || cosignerData)
        address signer = ecrecover(keccak256(abi.encodePacked(orderHash, abi.encode(order.cosignerData))), v, r, s);
        if (order.cosigner != signer || signer == address(0)) {
            revert InvalidCosignature();
        }
    }
}
