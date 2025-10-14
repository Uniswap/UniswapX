// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IAuctionResolver} from "../interfaces/IAuctionResolver.sol";
import {SignedOrder, InputToken, OutputToken} from "../../base/ReactorStructs.sol";
import {ResolvedOrder} from "../base/ReactorStructs.sol";
import {PriorityInput, PriorityOutput} from "../../lib/PriorityOrderLib.sol";
import {PriorityOrder, PriorityOrderLib} from "../lib/PriorityOrderLib.sol";
import {PriorityFeeLib} from "../../lib/PriorityFeeLib.sol";
import {CosignerLib} from "../../lib/CosignerLib.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";

/// @notice Auction resolver for priority fee based orders
contract PriorityAuctionResolver is IAuctionResolver {
    using PriorityOrderLib for PriorityOrder;
    using PriorityFeeLib for PriorityInput;
    using PriorityFeeLib for PriorityOutput;
    using PriorityFeeLib for PriorityOutput[];

    /// @notice thrown when an order's deadline is in the past
    error InvalidDeadline();
    /// @notice thrown when an order's auctionStartBlock is in the future
    error OrderNotFillable();
    /// @notice thrown when an order's nonce has already been used
    error OrderAlreadyFilled();
    /// @notice thrown when an order's input and outputs both scale with priority fee
    error InputOutputScaling();
    /// @notice thrown when tx gasprice is less than block.basefee
    error InvalidGasPrice();

    /// @notice Permit2 instance for nonce checking
    IPermit2 public immutable permit2;

    constructor(IPermit2 _permit2) {
        permit2 = _permit2;
    }

    /// @inheritdoc IAuctionResolver
    function resolve(SignedOrder calldata signedOrder)
        external
        view
        override
        returns (ResolvedOrder memory resolvedOrder)
    {
        PriorityOrder memory order = abi.decode(signedOrder.order, (PriorityOrder));

        _checkPermit2Nonce(order.info.swapper, order.info.nonce);

        bytes32 orderHash = order.hash();

        _validateOrder(orderHash, order);

        uint256 priorityFee = _getPriorityFee(order.baselinePriorityFeeWei);

        InputToken memory scaledInput = order.input.scale(priorityFee);
        OutputToken[] memory scaledOutputs = order.outputs.scale(priorityFee);

        resolvedOrder = ResolvedOrder({
            info: order.info,
            input: scaledInput,
            outputs: scaledOutputs,
            sig: signedOrder.sig,
            hash: orderHash,
            auctionResolver: address(this)
        });
    }

    /// @inheritdoc IAuctionResolver
    function getPermit2OrderType() external pure override returns (string memory) {
        return PriorityOrderLib.PERMIT2_ORDER_TYPE;
    }

    /// @notice validate the priority order fields
    /// - deadline must be in the future
    /// - resolved auctionStartBlock must not be in the future
    /// - if input scales with priority fee, outputs must not scale
    /// @dev Throws if the order is invalid
    function _validateOrder(bytes32 orderHash, PriorityOrder memory order) internal view {
        uint256 auctionStartBlock = order.auctionStartBlock;

        // we override auctionStartBlock with the cosigned auctionTargetBlock only if:
        // - cosigner is specified
        // - current block is before the auctionStartBlock signed by the user
        // - cosigned auctionTargetBlock is before the auctionStartBlock signed by the user
        if (
            order.cosigner != address(0) && block.number < auctionStartBlock
                && order.cosignerData.auctionTargetBlock < auctionStartBlock
        ) {
            CosignerLib.verify(order.cosigner, order.cosignerDigest(orderHash), order.cosignature);

            auctionStartBlock = order.cosignerData.auctionTargetBlock;
        }

        /// revert if the resolved auctionStartBlock is in the future
        if (block.number < auctionStartBlock) {
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

    /// @notice check if an order has already been filled
    /// @dev implementation copied from https://github.com/Uniswap/permit2/blob/cc56ad0f3439c502c246fc5cfcc3db92bb8b7219/src/SignatureTransfer.sol#L150
    /// @param swapper the address of the swapper
    /// @param nonce the nonce associated with the order
    function _checkPermit2Nonce(address swapper, uint256 nonce) internal view {
        uint256 wordPos = uint248(nonce >> 8);
        uint256 bit = 1 << uint8(nonce); // bitPos
        uint256 bitmap = permit2.nonceBitmap(swapper, wordPos);
        uint256 flipped = bitmap ^ bit;

        if (flipped & bit == 0) revert OrderAlreadyFilled();
    }
}
