// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {BaseReactor} from "./BaseReactor.sol";
import {SignedOrder, ResolvedOrder, InputToken, OrderInfo, OutputToken, Signature} from "../base/ReactorStructs.sol";

/// @dev An amount of tokens that decays linearly over time
struct DutchOutput {
    // The ERC20 token address
    address token;
    // The amount of tokens at the start of the time period
    uint256 startAmount;
    // The amount of tokens at the end of the time period
    uint256 endAmount;
    // The address who must receive the tokens to satisfy the order
    address recipient;
}

struct DutchInput {
    address token;
    uint256 startAmount;
    uint256 endAmount;
}

struct DutchLimitOrder {
    // generic order information
    OrderInfo info;
    // The time at which the DutchOutputs start decaying
    uint256 startTime;
    // endTime is implicitly info.deadline

    // The tokens that the offerer will provide when settling the order
    DutchInput input;
    // The tokens that must be received to satisfy the order
    DutchOutput[] outputs;
}

/// @notice Reactor for dutch limit orders
contract DutchLimitOrderReactor is BaseReactor {
    using FixedPointMathLib for uint256;

    error EndTimeBeforeStart();
    error InputAndOutputDecay();
    error IncorrectAmounts();

    constructor(address _permitPost) BaseReactor(_permitPost) {}

    /// @notice Resolve a DutchLimitOrder into a generic order
    /// @dev applies dutch decay to order outputs or order input
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
            hash: keccak256(signedOrder.order)
        });
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
