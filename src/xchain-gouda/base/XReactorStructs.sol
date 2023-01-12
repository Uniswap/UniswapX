// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {InputToken} from "../../base/ReactorStructs.sol";

/// @dev generic cross-chain order information
///  should be included as the first field in any concrete cross-chain order types
struct XOrderInfo {
    // The address of the reactor that this order is targeting
    // Note that this must be included in every order so the offerer
    // signature commits to the specific reactor that they trust to fill their order properly
    address reactor;
    // The address of the user which created the order
    // Note that this must be included so that order hashes are unique by offerer
    address offerer;
    // The nonce of the order, allowing for signature replay protection and cancellation
    uint256 nonce;
    // The timestamp after which this order is no longer valid to initiateSettlement
    uint256 fillDeadline;
    // The timestamp after which the order may be cancelled if it has not been settled
    uint256 settlementDeadline;
    // The address of the oracle that determines whether the order was sucessfully carried
    // out on the output chain
    address settlementOracle;
    // Custom validation contract
    address validationContract;
    // Encoded validation params for validationContract
    bytes validationData;
}

struct XCollateralToken {
  address token;
  uint256 amount;
}

/// @dev tokens that need to be received by the recipient on another chain in order to satisfy an order
struct XOutputToken {
    address token;
    uint256 amount;
    address recipient;
    uint256 chainId;
}

/// @dev generic concrete cross-chain order that specifies exact tokens which need to be sent and received
struct ResolvedXOrder {
    XOrderInfo info;
    InputToken input;
    XCollateralToken collateral;
    XOutputToken[] outputs;
    bytes sig;
    bytes32 hash;
}
