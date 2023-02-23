// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {InputToken} from "../../base/ReactorStructs.sol";

enum SettlementStatus {
    Pending,
    Challenged,
    Cancelled,
    Success
}

/// @dev generic cross-chain order information
/// should be included as the first field in any concrete cross-chain order type
struct SettlementInfo {
    // The address of the settler that this order is targeting
    address settlerContract;
    // The address of the user which created the order
    address offerer;
    // The nonce of the order, allowing for signature replay protection and cancellation
    uint256 nonce;
    // The timestamp after which this order is no longer valid to initiate
    uint256 initiateDeadline;
    // The time period in seconds the filler has to fill the order on the targetChain
    uint32 fillPeriod;
    // The time period in seconds when passed the filler may claim input and collateral tokens unless challenged
    uint32 optimisticSettlementPeriod;
    // The time period in seconds from the time of the settlement initialization that the filler has to prove a
    // challenged fill before the settlement can be cancelled
    uint32 challengePeriod;
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
    address originChainFiller;
    address targetChainFiller;
    address challenger;
    address settlementOracle;
    uint32 fillDeadline;
    uint32 optimisticDeadline;
    uint32 challengeDeadline;
    InputToken input;
    CollateralToken fillerCollateral;
    CollateralToken challengerCollateral;
    OutputToken[] outputs;
}

/// @dev generic concrete cross-chain order that specifies exact tokens which need to be sent and received
struct ResolvedOrder {
    SettlementInfo info;
    InputToken input;
    CollateralToken fillerCollateral;
    CollateralToken challengerCollateral;
    OutputToken[] outputs;
    bytes sig;
    bytes32 hash;
}
