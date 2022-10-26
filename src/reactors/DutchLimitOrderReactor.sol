// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {BaseReactor} from "./BaseReactor.sol";
import {Permit2Lib} from "../lib/Permit2Lib.sol";
import {OrderHash} from "../lib/OrderHash.sol";
import {SignedOrder, ResolvedOrder, InputToken, OrderInfo, OutputToken} from "../base/ReactorStructs.sol";

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

struct DutchLimitOrder {
    // generic order information
    OrderInfo info;
    // The time at which the DutchOutputs start decaying
    uint256 startTime;
    // endTime is implicitly info.deadline

    // The tokens that the offerer will provide when settling the order
    InputToken input;
    // The tokens that must be received to satisfy the order
    DutchOutput[] outputs;
}

/// @notice Reactor for dutch limit orders
contract DutchLimitOrderReactor is BaseReactor {
    using FixedPointMathLib for uint256;
    using Permit2Lib for ResolvedOrder;
    using OrderHash for OrderInfo;
    using OrderHash for InputToken;

    error EndTimeBeforeStart();
    error NegativeDecay();

    string private constant ORDER_TYPE_NAME = "DutchLimitOrder";
    bytes private constant DUTCH_OUTPUT_TYPE =
        "DutchOutput(address token,uint256 startAmount,uint256 endAmount,address recipient)";
    bytes32 private constant DUTCH_OUTPUT_TYPE_HASH = keccak256(DUTCH_OUTPUT_TYPE);
    bytes private constant ORDER_TYPE = abi.encodePacked(
        "DutchLimitOrder(OrderInfo info,uint256 startTime,InputToken input,DutchOutput[] outputs)",
        DUTCH_OUTPUT_TYPE,
        OrderHash.INPUT_TOKEN_TYPE,
        OrderHash.ORDER_INFO_TYPE
    );
    bytes32 private constant ORDER_TYPE_HASH = keccak256(ORDER_TYPE);

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
            hash: _hash(dutchLimitOrder)
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
            ORDER_TYPE_NAME,
            string(ORDER_TYPE),
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

    /// @notice hash the given order
    /// @param order the order to hash
    /// @return the eip-712 order hash
    function _hash(DutchLimitOrder memory order) internal pure returns (bytes32) {
        bytes32[] memory outputHashes = new bytes32[](order.outputs.length);
        for (uint256 i = 0; i < order.outputs.length; i++) {
            outputHashes[i] = keccak256(
                abi.encode(
                    DUTCH_OUTPUT_TYPE_HASH,
                    order.outputs[i].token,
                    order.outputs[i].startAmount,
                    order.outputs[i].endAmount,
                    order.outputs[i].recipient
                )
            );
        }
        bytes32 outputHash = keccak256(abi.encodePacked(outputHashes));

        return keccak256(
            abi.encode(ORDER_TYPE_HASH, order.info.hash(), order.startTime, order.input.hash(), outputHash)
        );
    }
}
