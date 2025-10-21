// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {PriceCurveLib} from "tribunal/src/lib/PriceCurveLib.sol";

import {IAuctionResolver} from "../interfaces/IAuctionResolver.sol";
import {SignedOrder, InputToken, OutputToken} from "../../base/ReactorStructs.sol";
import {ResolvedOrder} from "../base/ReactorStructs.sol";
import {HybridOrder, HybridOrderLib, HybridInput, HybridOutput} from "../lib/HybridOrderLib.sol";
import {CosignerLib} from "../../lib/CosignerLib.sol";

/// @notice Resolver for hybrid Dutch + priority gas auctions following Tribunal's model
contract HybridAuctionResolver is IAuctionResolver {
    using HybridOrderLib for HybridOrder;
    using HybridOrderLib for HybridOutput[];
    using HybridOrderLib for HybridInput;
    using PriceCurveLib for uint256[];
    using PriceCurveLib for uint256;

    /// @notice Base scaling factor (1e18).
    uint256 public constant BASE_SCALING_FACTOR = 1e18;

    error InvalidAuctionBlock();
    error InvalidGasPrice();

    /// @inheritdoc IAuctionResolver
    function resolve(SignedOrder calldata signedOrder)
        external
        view
        override
        returns (ResolvedOrder memory resolvedOrder)
    {
        HybridOrder memory order = abi.decode(signedOrder.order, (HybridOrder));

        // Extract cosigner data and determine target block + supplemental curve
        uint256 auctionTargetBlock = order.auctionStartBlock;
        uint256[] memory effectivePriceCurve = order.priceCurve;

        if (order.cosigner != address(0)) {
            // Verify cosigner signature
            bytes32 orderHash = order.hash();
            CosignerLib.verify(order.cosigner, order.cosignerDigest(orderHash), order.cosignature);

            if (order.cosignerData.auctionTargetBlock != 0) {
                auctionTargetBlock = order.cosignerData.auctionTargetBlock;
            }

            if (order.cosignerData.supplementalPriceCurve.length > 0) {
                effectivePriceCurve =
                    order.priceCurve.applyMemorySupplementalPriceCurve(order.cosignerData.supplementalPriceCurve);
            }
        }

        if (auctionTargetBlock != 0 && block.number < auctionTargetBlock) {
            revert InvalidAuctionBlock();
        }

        uint256 currentScalingFactor =
            HybridOrderLib.deriveCurrentScalingFactor(order, effectivePriceCurve, auctionTargetBlock, block.number);

        uint256 scalingMultiplier;
        // When neutral (scalingFactor == 1e18), determine mode from currentScalingFactor
        bool useExactIn = (order.scalingFactor > BASE_SCALING_FACTOR)
            || (order.scalingFactor == BASE_SCALING_FACTOR && currentScalingFactor >= BASE_SCALING_FACTOR);

        uint256 priorityFeeAboveBaseline = _getPriorityFee(order.baselinePriorityFee);
        if (useExactIn) {
            scalingMultiplier =
                currentScalingFactor + ((order.scalingFactor - BASE_SCALING_FACTOR) * priorityFeeAboveBaseline);
            resolvedOrder = ResolvedOrder({
                info: order.info,
                input: InputToken({
                    token: order.input.token,
                    amount: order.input.maxAmount,
                    maxAmount: order.input.maxAmount
                }),
                outputs: order.outputs.scale(scalingMultiplier),
                sig: signedOrder.sig,
                hash: order.hash(),
                auctionResolver: address(this)
            });
        } else {
            scalingMultiplier =
                currentScalingFactor - ((BASE_SCALING_FACTOR - order.scalingFactor) * priorityFeeAboveBaseline);
            OutputToken[] memory outputs = new OutputToken[](order.outputs.length);
            for (uint256 i = 0; i < order.outputs.length; i++) {
                outputs[i] = OutputToken({
                    token: order.outputs[i].token,
                    amount: order.outputs[i].minAmount,
                    recipient: order.outputs[i].recipient
                });
            }
            resolvedOrder = ResolvedOrder({
                info: order.info,
                input: order.input.scale(scalingMultiplier),
                outputs: outputs,
                sig: signedOrder.sig,
                hash: order.hash(),
                auctionResolver: address(this)
            });
        }
    }

    /// @inheritdoc IAuctionResolver
    function getPermit2OrderType() external pure override returns (string memory) {
        return HybridOrderLib.PERMIT2_ORDER_TYPE;
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
