// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {BaseReactor} from "./BaseReactor.sol";
import {Permit2Lib} from "../lib/Permit2Lib.sol";
import {DutchLimitOrderLib, DutchLimitOrder, DutchOutput} from "../lib/DutchLimitOrderLib.sol";
import {SignedOrder, ResolvedOrder, InputToken, OrderInfo, OutputToken} from "../base/ReactorStructs.sol";

/// @notice Reactor for dutch limit orders
contract DutchLimitOrderReactor is BaseReactor {
    using FixedPointMathLib for uint256;
    using Permit2Lib for ResolvedOrder;
    using DutchLimitOrderLib for DutchLimitOrder;

    error EndTimeBeforeStart();
    error NegativeDecay();

    constructor(address _permit2) BaseReactor(_permit2) {}

    /// @inheritdoc BaseReactor
    function resolve(SignedOrder memory signedOrder)
        internal
        view
        virtual
        override
        returns (ResolvedOrder memory resolvedOrder)
    {
        DutchLimitOrder memory dutchLimitOrder = abi.decode(signedOrder.order, (DutchLimitOrder));
        _validateOrder(dutchLimitOrder);

        OutputToken[] memory outputs = new OutputToken[](dutchLimitOrder.outputs.length);
        for (uint256 i = 0; i < outputs.length; i++) {
            DutchOutput memory output = dutchLimitOrder.outputs[i];
            uint256 decayedAmount;

            if (output.startAmount < output.endAmount) {
                revert NegativeDecay();
            } else if (dutchLimitOrder.info.deadline == block.timestamp || output.startAmount == output.endAmount) {
                decayedAmount = output.endAmount;
            } else if (dutchLimitOrder.startTime >= block.timestamp) {
                decayedAmount = output.startAmount;
            } else {
                // TODO: maybe handle case where startAmount < endAmount
                // i.e. for exactOutput case
                uint256 elapsed = block.timestamp - dutchLimitOrder.startTime;
                uint256 duration = dutchLimitOrder.info.deadline - dutchLimitOrder.startTime;
                uint256 decayAmount = output.startAmount - output.endAmount;
                decayedAmount = output.startAmount - decayAmount.mulDivDown(elapsed, duration);
            }
            outputs[i] = OutputToken(output.token, decayedAmount, output.recipient);
        }
        resolvedOrder = ResolvedOrder({
            info: dutchLimitOrder.info,
            input: dutchLimitOrder.input,
            outputs: outputs,
            sig: signedOrder.sig,
            hash: dutchLimitOrder.hash()
        });
    }

    /// @inheritdoc BaseReactor
    function transferInputTokens(ResolvedOrder memory order, address to) internal override {
        permit2.permitWitnessTransferFrom(
            order.toPermit(),
            order.info.offerer,
            to,
            order.input.amount,
            order.hash,
            DutchLimitOrderLib.ORDER_TYPE_NAME,
            string(DutchLimitOrderLib.ORDER_TYPE),
            order.sig
        );
    }

    /// @notice validate the dutch order fields
    /// @dev Throws if the order is invalid
    function _validateOrder(DutchLimitOrder memory dutchLimitOrder) internal pure {
        if (dutchLimitOrder.info.deadline <= dutchLimitOrder.startTime) {
            revert EndTimeBeforeStart();
        }
    }
}
