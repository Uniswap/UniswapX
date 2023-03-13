// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

address constant ETH_ADDRESS = 0x0000000000000000000000000000000000000000;

/// @dev generic order information
///  should be included as the first field in any concrete order types
struct OrderInfo {
    // The address of the reactor that this order is targeting
    // Note that this must be included in every order so the offerer
    // signature commits to the specific reactor that they trust to fill their order properly
    address reactor;
    // The address of the user which created the order
    // Note that this must be included so that order hashes are unique by offerer
    address offerer;
    // The nonce of the order, allowing for signature replay protection and cancellation
    uint256 nonce;
    // The timestamp after which this order is no longer valid
    uint256 deadline;
    // Custom validation contract
    address validationContract;
    // Encoded validation params for validationContract
    bytes validationData;
}

/// @dev tokens that need to be sent from the offerer in order to satisfy an order
struct InputToken {
    address token;
    uint256 amount;
    // Needed for dutch decaying inputs
    uint256 maxAmount;
}

/// @dev tokens that need to be received by the recipient in order to satisfy an order
struct OutputToken {
    address token;
    uint256 amount;
    address recipient;
    bool isFeeOutput;
}

/// @dev generic concrete order that specifies exact tokens which need to be sent and received
struct ResolvedOrder {
    OrderInfo info;
    InputToken input;
    OutputToken[] outputs;
    bytes sig;
    bytes32 hash;
}

/// @dev external struct including a generic encoded order and offerer signature
///  The order bytes will be parsed and mapped to a ResolvedOrder in the concrete reactor contract
struct SignedOrder {
    bytes order;
    bytes sig;
}
