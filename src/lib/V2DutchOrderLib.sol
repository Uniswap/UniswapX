// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {OrderInfo} from "../base/ReactorStructs.sol";
import {DutchOutput, DutchInput, DutchOrderLib} from "./DutchOrderLib.sol";
import {OrderInfoLib} from "./OrderInfoLib.sol";

struct V2DutchOrderInner {
    // generic order information
    OrderInfo info;
    // The address which must cosign the ful order
    address cosigner;
    // The tokens that the swapper will provide when settling the order
    DutchInput input;
    // The tokens that must be received to satisfy the order
    DutchOutput[] outputs;
}

struct V2DutchOrder {
    // Inner order
    V2DutchOrderInner inner;
    // The time at which the DutchOutputs start decaying
    uint256 decayStartTime;
    // The time at which price becomes static
    uint256 decayEndTime;
    // The address who has exclusive rights to the order until decayStartTime
    address exclusiveFiller;
    // The amount in bps that a non-exclusive filler needs to improve the outputs by to be able to fill the order
    uint256 exclusivityOverrideBps;
    // The tokens that the swapper will provide when settling the order
    uint256 inputOverride;
    // The tokens that must be received to satisfy the order
    uint256[] outputOverrides;
}

struct CosignedV2DutchOrder {
    V2DutchOrder order;
    bytes signature;
}

/// @notice helpers for handling v2 dutch order objects
library V2DutchOrderLib {
    using DutchOrderLib for DutchOutput[];
    using OrderInfoLib for OrderInfo;

    bytes internal constant V2_DUTCH_ORDER_TYPE = abi.encodePacked(
        "V2DutchOrder(",
        "OrderInfo info,",
        "address cosigner,",
        "address inputToken,",
        "uint256 inputStartAmount,",
        "uint256 inputEndAmount,",
        "DutchOutput[] outputs)"
    );

    bytes internal constant ORDER_TYPE =
        abi.encodePacked(V2_DUTCH_ORDER_TYPE, DutchOrderLib.DUTCH_OUTPUT_TYPE, OrderInfoLib.ORDER_INFO_TYPE);
    bytes32 internal constant ORDER_TYPE_HASH = keccak256(ORDER_TYPE);

    /// @dev Note that sub-structs have to be defined in alphabetical order in the EIP-712 spec
    string internal constant PERMIT2_ORDER_TYPE = string(
        abi.encodePacked(
            "V2DutchOrder witness)",
            DutchOrderLib.DUTCH_OUTPUT_TYPE,
            OrderInfoLib.ORDER_INFO_TYPE,
            DutchOrderLib.TOKEN_PERMISSIONS_TYPE,
            V2_DUTCH_ORDER_TYPE
        )
    );

    /// @notice hash the given order
    /// @param order the order to hash
    /// @return the eip-712 order hash
    function hash(V2DutchOrder memory order) internal pure returns (bytes32) {
        V2DutchOrderInner memory inner = order.inner;
        return keccak256(
            abi.encode(
                ORDER_TYPE_HASH,
                inner.info.hash(),
                inner.cosigner,
                inner.input.token,
                inner.input.startAmount,
                inner.input.endAmount,
                inner.outputs.hash()
            )
        );
    }
}
