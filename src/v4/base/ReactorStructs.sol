// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IReactor} from "../../interfaces/IReactor.sol";
import {IPreExecutionHook, IPostExecutionHook} from "../interfaces/IHook.sol";
import {InputToken, OutputToken} from "../../base/ReactorStructs.sol";

/// @dev generic order information
///  should be included as the first field in any concrete order types
struct OrderInfo {
    // The address of the reactor that this order is targeting
    // Note that this must be included in every order so the swapper
    // signature commits to the specific reactor that they trust to fill their order properly
    IReactor reactor;
    // The address of the user which created the order
    // Note that this must be included so that order hashes are unique by swapper
    address swapper;
    // The nonce of the order, allowing for signature replay protection and cancellation
    uint256 nonce;
    // The timestamp after which this order is no longer valid
    uint256 deadline;
    // Pre-execution hook contract
    IPreExecutionHook preExecutionHook;
    // Encoded pre-execution hook data
    bytes preExecutionHookData;
    // Post-execution hook contract
    IPostExecutionHook postExecutionHook;
    // Encoded post-execution hook data
    bytes postExecutionHookData;
}

/// @dev generic concrete order that specifies exact tokens which need to be sent and received
struct ResolvedOrder {
    OrderInfo info;
    InputToken input;
    OutputToken[] outputs;
    bytes sig;
    bytes32 hash;
    address auctionResolver;
}
