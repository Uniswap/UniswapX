// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {OrderHash} from "../../src/lib/OrderHash.sol";
import {OrderInfo, InputToken, OutputToken} from "../../src/base/ReactorStructs.sol";
import {LimitOrderReactor, LimitOrder} from "../../src/reactors/LimitOrderReactor.sol";
import {DutchLimitOrder} from "../../src/reactors/DutchLimitOrderReactor.sol";

contract TestOrderHashing {
    using OrderHash for OrderInfo;
    using OrderHash for InputToken;
    using OrderHash for OutputToken[];

    string constant TYPEHASH_STUB =
        "PermitWitnessTransferFrom(address token,address spender,uint256 signedAmount,uint256 nonce,uint256 deadline,";

    bytes constant LIMIT_ORDER_TYPE = abi.encodePacked(
        "LimitOrder(",
        "address reactor,",
        "address offerer,",
        "uint256 nonce,",
        "uint256 deadline,",
        "address inputToken,",
        "uint256 inputAmount,",
        "OutputToken[] outputs)",
        OrderHash.OUTPUT_TOKEN_TYPE
    );
    bytes32 constant LIMIT_ORDER_TYPE_HASH_INNER = keccak256(LIMIT_ORDER_TYPE);
    bytes32 constant LIMIT_ORDER_TYPE_HASH =
        keccak256(abi.encodePacked(TYPEHASH_STUB, "LimitOrder", " witness)", LIMIT_ORDER_TYPE));

    bytes constant DUTCH_OUTPUT_TYPE =
        "DutchOutput(address token,uint256 startAmount,uint256 endAmount,address recipient)";
    bytes32 constant DUTCH_OUTPUT_TYPE_HASH = keccak256(DUTCH_OUTPUT_TYPE);
    bytes constant DUTCH_ORDER_TYPE = abi.encodePacked(
        "DutchLimitOrder(",
        "address reactor,",
        "address offerer,",
        "uint256 nonce,",
        "uint256 deadline,",
        "uint256 startTime,",
        "address inputToken,",
        "uint256 inputAmount,",
        "DutchOutput[] outputs)",
        DUTCH_OUTPUT_TYPE
    );
    bytes32 constant DUTCH_ORDER_TYPE_HASH_INNER = keccak256(DUTCH_ORDER_TYPE);
    bytes32 constant DUTCH_ORDER_TYPE_HASH =
        keccak256(abi.encodePacked(TYPEHASH_STUB, "DutchLimitOrder", " witness)", DUTCH_ORDER_TYPE));

    function hash(LimitOrder memory order) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                LIMIT_ORDER_TYPE_HASH_INNER,
                order.info.reactor,
                order.info.offerer,
                order.info.nonce,
                order.info.deadline,
                order.input.token,
                order.input.amount,
                order.outputs.hash()
            )
        );
    }

    function hash(DutchLimitOrder memory order) internal pure returns (bytes32) {
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
            abi.encode(
                DUTCH_ORDER_TYPE_HASH_INNER,
                order.info.reactor,
                order.info.offerer,
                order.info.nonce,
                order.info.deadline,
                order.startTime,
                order.input.token,
                order.input.amount,
                outputHash
            )
        );
    }
}
