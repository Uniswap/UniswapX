// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IReactor} from "../interfaces/IReactor.sol";
import {IPreExecutionHook, IPostExecutionHook} from "../interfaces/IHook.sol";
import {IAuctionResolver} from "../interfaces/IAuctionResolver.sol";
import {InputToken, OutputToken} from "../../base/ReactorStructs.sol";

/// @notice GenericOrder wraps resolver-specific orders with resolver address
/// @dev This struct is used as the Permit2 witness to bind the resolver address to the order hash
struct GenericOrder {
    address resolver;
    bytes32 orderHash;
}

//@dev Type hash for GenericOrder struct used in EIP-712 signatures
bytes32 constant GENERIC_ORDER_TYPE_HASH = keccak256("GenericOrder(address resolver,bytes32 orderHash)");

//@dev Witness type string for GenericOrder used in Permit2's permitWitnessTransferFrom
//@dev This gets concatenated with Permit2's stub to form the complete witness type string
string constant GENERIC_ORDER_WITNESS_TYPE =
    "GenericOrder witness)GenericOrder(address resolver,bytes32 orderHash)TokenPermissions(address token,uint256 amount)";

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
    // Auction resolver contract
    IAuctionResolver auctionResolver;
}

/// @dev generic concrete order that specifies exact tokens which need to be sent and received
struct ResolvedOrder {
    OrderInfo info;
    InputToken input;
    OutputToken[] outputs;
    bytes sig;
    bytes32 hash; // The witness hash that includes resolver address and full order (what was signed)
    address auctionResolver;
    // Witness type string provided by resolver for Permit2 verification
    string witnessTypeString;
}
