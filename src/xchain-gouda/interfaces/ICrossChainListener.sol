// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {ResolvedOrder} from "../base/SettlementStructs.sol";
import {SignedOrder} from "../../base/ReactorStructs.sol";

struct SettlementFillInfo {
  uint32 chainId;
  address filler;
  address recipient;
  address token;
  uint256 amount;
}

/// @notice Interface for cross chain listeners for gouda
interface ICrossChainListener {
    /// @notice Get the settlementInfo associated with an orderId.
    /// @param orderId The cross-chain orderId
    /// @return settlementInfo The settlmentInfo that was passed to the cross-chain listener from a valid source
    function getSettlementFillInfo(bytes32 orderId) external view returns (SettlementFillInfo[] calldata);

    /// @notice Logs the settlement info given for an orderId
    /// @dev Access to this function must be restricted to valid message bridges and must verify that chainId corresponds
    /// to the correct bridge.
    /// @param settlementInfo The settlmentInfo that should be logged for a given orderId
    /// @param orderId The cross-chain orderId
    function logSettlementFillInfo(SettlementFillInfo[] calldata settlementInfo, bytes32 orderId) external;
}
