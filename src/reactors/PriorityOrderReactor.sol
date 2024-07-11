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
    /// @notice thrown when tx gasprice is less than block.basefee
    error InvalidGasPrice();

    constructor(IPermit2 _permit2, address _protocolFeeOwner) BaseReactor(_permit2, _protocolFeeOwner) {}

    /// @inheritdoc BaseReactor
    function _resolve(SignedOrder calldata signedOrder)
        internal
        view
        override
        returns (ResolvedOrder memory resolvedOrder)
    {
        PriorityOrder memory order = abi.decode(signedOrder.order, (PriorityOrder));
        bytes32 orderHash = order.hash();

        if (block.number < order.auctionStartBlock) {
            _updateWithCosignerData(orderHash, order);
        }
        _validateOrder(order);

        uint256 priorityFee = _getPriorityFee(order.baselinePriorityFeeWei);

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

    /// @notice update the priority order with the cosigner's data
    /// @dev only called if the current block is before the auctionStartBlock signed by the user
    /// @param orderHash the hash of the order
    /// @param order the order to update
    function _updateWithCosignerData(bytes32 orderHash, PriorityOrder memory order) internal pure {
        /// return quickly if cosignerData is not set
        if (order.cosignerData.auctionTargetBlock == 0) return;

        if (order.cosignerData.auctionTargetBlock < order.auctionStartBlock) {
            order.auctionStartBlock = order.cosignerData.auctionTargetBlock;
        }
        // validate cosigner signature
        (bytes32 r, bytes32 s) = abi.decode(order.cosignature, (bytes32, bytes32));
        uint8 v = uint8(order.cosignature[64]);
        // cosigner signs over (orderHash || cosignerData)
        address signer = ecrecover(keccak256(abi.encodePacked(orderHash, abi.encode(order.cosignerData))), v, r, s);
        if (order.cosigner != signer || signer == address(0)) {
            revert InvalidCosignature();
        }
    }

    /// @notice validate the priority order fields
    /// - deadline must be in the future
    /// - auctionStartBlock must not be in the future
    /// - if input scales with priority fee, outputs must not scale
    /// - order's cosigner must have signed over (orderHash || cosignerData)
    /// @dev Throws if the order is invalid
    function _validateOrder(PriorityOrder memory order) internal view {
        if (order.info.deadline < block.timestamp) {
            revert InvalidDeadline();
        }

        /// revert if the resolved auctionStartBlock is in the future
        /// must be the minimum(auctionStartBlock, cosignerData.auctionTargetBlock)
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
    }

    /// @notice resolve the priority fee for the current transaction
    /// @notice tx.gasprice must be greater than or equal to block.basefee
    /// @param baselinePriorityFeeWei the baseline priority fee to be subtracted from calculated priority fee
    /// @return priorityFee the resolved priority fee
    function _getPriorityFee(uint256 baselinePriorityFeeWei) internal view returns (uint256 priorityFee) {
        if (tx.gasprice < block.basefee) revert InvalidGasPrice();
        unchecked {
            priorityFee = tx.gasprice - block.basefee;
            if (priorityFee > baselinePriorityFeeWei) {
                priorityFee -= baselinePriorityFeeWei;
            } else {
                priorityFee = 0;
            }
        }
    }
}
