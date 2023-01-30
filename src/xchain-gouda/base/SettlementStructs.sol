// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {InputToken} from "../../base/ReactorStructs.sol";

enum SettlementStatus {
    Pending,
    Cancelled,
    Filled
}

/// @dev generic cross-chain order information
///  should be included as the first field in any concrete cross-chain order types
struct SettlementInfo {
    // The address of the settler that this order is targeting
    address settlerContract;
    // The address of the user which created the order
    address offerer;
    // The nonce of the order, allowing for signature replay protection and cancellation
    uint256 nonce;
    // The timestamp after which this order is no longer valid to initiateSettlement
    uint256 fillDeadline;
    // The time period in seconds for which the settlement cannot be cancelled, giving the filler time to fill the order
    uint256 settlementPeriod;
    // Contract that receives information about cross chain transactions
    address settlementOracle;
    // Custom validation contract
    address validationContract;
    // Encoded validation params for validationContract
    bytes validationData;
}

struct CollateralToken {
    address token;
    uint256 amount;
}

/// @dev tokens that need to be received by the recipient on another chain in order to satisfy an order
struct OutputToken {
    address recipient;
    address token;
    uint256 amount;
    uint256 chainId;
}

struct ActiveSettlement {
    SettlementStatus status;
    address offerer;
    address fillRecipient;
    address crossChainFiller;
    address settlementOracle;
    uint256 deadline;
    InputToken input;
    CollateralToken collateral;
    OutputToken[] outputs;
}

/// @dev generic concrete cross-chain order that specifies exact tokens which need to be sent and received
struct ResolvedOrder {
    SettlementInfo info;
    InputToken input;
    CollateralToken collateral;
    OutputToken[] outputs;
    bytes sig;
    bytes32 hash;
}
