// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {BaseReactor} from "./BaseReactor.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {Permit2Lib} from "../lib/Permit2Lib.sol";
import {DutchDecayLib} from "../lib/DutchDecayLib.sol";
import {
    ExclusiveDutchLimitOrderLib,
    ExclusiveDutchLimitOrder,
    DutchOutput,
    DutchInput
} from "../lib/ExclusiveDutchLimitOrderLib.sol";
import {SignedOrder, ResolvedOrder, InputToken, OrderInfo, OutputToken} from "../base/ReactorStructs.sol";

/// @notice Reactor for exclusive dutch limit orders
contract ExclusiveDutchLimitOrderReactor is BaseReactor {
    using Permit2Lib for ResolvedOrder;
    using FixedPointMathLib for uint256;
    using ExclusiveDutchLimitOrderLib for ExclusiveDutchLimitOrder;
    using DutchDecayLib for DutchOutput[];
    using DutchDecayLib for DutchInput;

    uint256 private constant BPS = 10_000;

    error DeadlineBeforeEndTime();
    error EndTimeBeforeStartTime();
    error InputAndOutputDecay();

    constructor(address _permit2, uint256 _protocolFeeBps, address _protocolFeeRecipient)
        BaseReactor(_permit2, _protocolFeeBps, _protocolFeeRecipient)
    {}

    /// @inheritdoc BaseReactor
    function resolve(SignedOrder calldata signedOrder)
        internal
        view
        virtual
        override
        returns (ResolvedOrder memory resolvedOrder)
    {
        ExclusiveDutchLimitOrder memory order = abi.decode(signedOrder.order, (ExclusiveDutchLimitOrder));
        _validateOrder(order);

        resolvedOrder = ResolvedOrder({
            info: order.info,
            input: order.input.decay(order.startTime, order.endTime),
            // if the filler has fill right, they can fill at the specified price
            // else they must override the price by EXCLUSIVE_OVERRIDE_BPS
            outputs: _checkExclusivity(order) ? order.outputs.decay(order.startTime, order.endTime) : scaleOverride(order),
            sig: signedOrder.sig,
            hash: order.hash()
        });
    }

    /// @inheritdoc BaseReactor
    function transferInputTokens(ResolvedOrder memory order, address to) internal override {
        ISignatureTransfer(permit2).permitWitnessTransferFrom(
            order.toPermit(),
            order.transferDetails(to),
            order.info.offerer,
            order.hash,
            ExclusiveDutchLimitOrderLib.PERMIT2_ORDER_TYPE,
            order.sig
        );
    }

    /// @notice validate the dutch order fields
    /// - deadline must be greater than or equal than endTime
    /// - endTime must be greater than or equal to startTime
    /// - if there's input decay, outputs must not decay
    /// - for input decay, startAmount must < endAmount
    /// @dev Throws if the order is invalid
    function _validateOrder(ExclusiveDutchLimitOrder memory order) internal pure {
        if (order.info.deadline < order.endTime) {
            revert DeadlineBeforeEndTime();
        }

        if (order.endTime < order.startTime) {
            revert EndTimeBeforeStartTime();
        }

        if (order.input.startAmount != order.input.endAmount) {
            unchecked {
                for (uint256 i = 0; i < order.outputs.length; i++) {
                    if (order.outputs[i].startAmount != order.outputs[i].endAmount) {
                        revert InputAndOutputDecay();
                    }
                }
            }
        }
    }

    /// @notice checks if the order currently passes the exclusivity check
    /// @dev if the order has no exclusivity, always returns true
    /// @dev if the order has exclusivity and the current filler is the exlcusive address, returns true
    /// @dev if the order has exclusivity and the current filler is not the exlcusive address, returns false
    function _checkExclusivity(ExclusiveDutchLimitOrder memory order) internal view returns (bool pass) {
        address exclusive = order.exclusiveFiller;
        return exclusive == address(0) || block.timestamp > order.startTime || exclusive == msg.sender;
    }

    /// @notice returns a scaled output array by the exclusivity override amount
    /// @param order The order to scale
    /// @return result a scaled output array
    function scaleOverride(ExclusiveDutchLimitOrder memory order) internal pure returns (OutputToken[] memory result) {
        DutchOutput[] memory outputs = order.outputs;
        result = new OutputToken[](outputs.length);
        for (uint256 i = 0; i < outputs.length; i++) {
            DutchOutput memory output = outputs[i];
            uint256 scaledOutput = output.startAmount.mulDivDown(order.exclusivityOverrideBps, BPS);
            result[i] = OutputToken(output.token, scaledOutput, output.recipient, output.isFeeOutput);
        }
    }
}
