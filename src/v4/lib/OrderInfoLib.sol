// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {OrderInfo} from "../base/ReactorStructs.sol";

/// @notice helpers for handling OrderInfo objects
library OrderInfoLib {
    bytes internal constant ORDER_INFO_TYPE =
        "OrderInfo(address reactor,address swapper,uint256 nonce,uint256 deadline,address preExecutionHook,bytes preExecutionHookData,address postExecutionHook,bytes postExecutionHookData)";
    bytes32 internal constant ORDER_INFO_TYPE_HASH = keccak256(ORDER_INFO_TYPE);

    /// @notice hash an OrderInfo object
    /// @param info The OrderInfo object to hash
    function hash(OrderInfo memory info) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                ORDER_INFO_TYPE_HASH,
                info.reactor,
                info.swapper,
                info.nonce,
                info.deadline,
                info.preExecutionHook,
                keccak256(info.preExecutionHookData),
                info.postExecutionHook,
                keccak256(info.postExecutionHookData)
            )
        );
    }
}
