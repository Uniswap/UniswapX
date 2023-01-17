// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {InputToken} from "../../base/ReactorStructs.sol";

enum OrderStatus {
  Pending,
  Cancelled,
  Success
}

/// @dev generic cross-chain order information
///  should be included as the first field in any concrete cross-chain order types
struct SettlementInfo {
    // The address of the settlementoracle that this order is targeting
    address settlementOracle;
    // The address of the user which created the order
    address offerer;
    // The nonce of the order, allowing for signature replay protection and cancellation
    uint256 nonce;
    // The timestamp after which this order is no longer valid to initiateSettlement
    uint256 fillDeadline;
    // The duration in seconds that the filler has to settle an order after initiating it before it may be cancelled
    uint256 settlementPeriod;
    // Contract that receives information about cross chain transactions
    address crossChainListener;
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
    address token;
    uint256 amount;
    address recipient;
    uint256 chainId;
}

/// @dev generic concrete cross-chain order that specifies exact tokens which need to be sent and received
struct ResolvedOrder {
    SettlementInfo info;
    uint256 settlementDeadline;
    InputToken input;
    CollateralToken collateral;
    OutputToken[] outputs;
    address fillRecipient;
    OrderStatus status;
    bytes sig;
    bytes32 hash;
}
