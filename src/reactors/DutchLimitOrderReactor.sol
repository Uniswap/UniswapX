// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {BaseReactor} from "./BaseReactor.sol";
import {Permit2Lib} from "../lib/Permit2Lib.sol";
import {DutchLimitOrderLib, DutchLimitOrder, DutchOutput, DutchInput} from "../lib/DutchLimitOrderLib.sol";
import {IPSFees} from "../base/IPSFees.sol";
import {SignedOrder, ResolvedOrder, InputToken, OrderInfo, OutputToken} from "../base/ReactorStructs.sol";

/// @notice Reactor for dutch limit orders
contract DutchLimitOrderReactor is BaseReactor, IPSFees {
    using FixedPointMathLib for uint256;
    using Permit2Lib for ResolvedOrder;
    using DutchLimitOrderLib for DutchLimitOrder;

    error EndTimeBeforeStart();
    error InputAndOutputDecay();
    error IncorrectAmounts();

    constructor(address _permit2, uint256 _protocolFeeBps, address _protocolFeeRecipient)
        BaseReactor(_permit2)
        IPSFees(_protocolFeeBps, _protocolFeeRecipient)
    {}

    /// @inheritdoc BaseReactor
    function resolve(SignedOrder memory signedOrder)
        internal
        virtual
        override
        returns (ResolvedOrder memory resolvedOrder)
    {
        DutchLimitOrder memory dutchLimitOrder = abi.decode(signedOrder.order, (DutchLimitOrder));
        _validateOrder(dutchLimitOrder);

        OutputToken[] memory outputs = new OutputToken[](dutchLimitOrder.outputs.length);
        for (uint256 i = 0; i < outputs.length; i++) {
            DutchOutput memory output = dutchLimitOrder.outputs[i];
            if (output.startAmount < output.endAmount) {
                revert IncorrectAmounts();
            }
            uint256 decayedOutput = _getDecayedAmount(
                output.startAmount, output.endAmount, dutchLimitOrder.startTime, dutchLimitOrder.info.deadline
            );
            outputs[i] = OutputToken(output.token, decayedOutput, output.recipient);
        }

        uint256 decayedInput = _getDecayedAmount(
            dutchLimitOrder.input.startAmount,
            dutchLimitOrder.input.endAmount,
            dutchLimitOrder.startTime,
            dutchLimitOrder.info.deadline
        );
        resolvedOrder = ResolvedOrder({
            info: dutchLimitOrder.info,
            input: InputToken(dutchLimitOrder.input.token, decayedInput, dutchLimitOrder.input.endAmount),
            outputs: outputs,
            sig: signedOrder.sig,
            hash: dutchLimitOrder.hash()
        });
        _takeFees(resolvedOrder);
    }

    /// @inheritdoc BaseReactor
    function transferInputTokens(ResolvedOrder memory order, address to) internal override {
        permit2.permitWitnessTransferFrom(
            order.toPermit(),
            order.transferDetails(to),
            order.info.offerer,
            order.hash,
            DutchLimitOrderLib.PERMIT2_ORDER_TYPE,
            order.sig
        );
    }

    /// @notice validate the dutch order fields
    /// - deadline must be greater or equal than startTime
    /// - if there's input decay, outputs must not decay
    /// - for input decay, startAmount must < endAmount
    /// @dev Throws if the order is invalid
    function _validateOrder(DutchLimitOrder memory dutchLimitOrder) internal pure {
        if (dutchLimitOrder.info.deadline <= dutchLimitOrder.startTime) {
            revert EndTimeBeforeStart();
        }

        if (dutchLimitOrder.input.startAmount != dutchLimitOrder.input.endAmount) {
            if (dutchLimitOrder.input.startAmount > dutchLimitOrder.input.endAmount) {
                revert IncorrectAmounts();
            }
            for (uint256 i = 0; i < dutchLimitOrder.outputs.length; i++) {
                if (dutchLimitOrder.outputs[i].startAmount != dutchLimitOrder.outputs[i].endAmount) {
                    revert InputAndOutputDecay();
                }
            }
        }
    }

    /// @notice calculates an amount using linear decay over time from startTime to endTime
    /// @dev handles both positive and negative decay depending on startAmount and endAmount
    /// @param startAmount The amount of tokens at startTime
    /// @param endAmount The amount of tokens at endTime
    /// @param startTime The time to start decaying linearly
    /// @param endTime The time to stop decaying linearly
    function _getDecayedAmount(uint256 startAmount, uint256 endAmount, uint256 startTime, uint256 endTime)
        internal
        view
        returns (uint256 decayedAmount)
    {
        if (endTime == block.timestamp || startAmount == endAmount) {
            decayedAmount = endAmount;
        } else if (startTime >= block.timestamp) {
            decayedAmount = startAmount;
        } else {
            unchecked {
                uint256 elapsed = block.timestamp - startTime;
                uint256 duration = endTime - startTime;
                if (endAmount < startAmount) {
                    decayedAmount = startAmount - (startAmount - endAmount).mulDivDown(elapsed, duration);
                } else {
                    decayedAmount = startAmount + (endAmount - startAmount).mulDivDown(elapsed, duration);
                }
            }
        }
    }
}
