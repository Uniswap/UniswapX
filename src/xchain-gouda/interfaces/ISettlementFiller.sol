// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {OutputToken, SettlementKey} from "../base/SettlementStructs.sol";
import {SignedOrder} from "../../base/ReactorStructs.sol";

/// @notice Interface for target chain fillers for gouda. A SettlementFiller exists on the target chain, and carries out
/// transfers from the targetChainFiller to the output recipients in order to verify the stated outputs were filled successfully.
/// A SettlementFiller is associated with the swapper-selected SettlementOracle on the origin chain.
interface ISettlementFiller {
    /// @notice Thrown when the hash of the outputs array does not match the outputsHash in the SettlementKey
    error InvalidOutputsHash();

    /// @notice Thrown when output token does not match the chain id of this deployed contract
    /// @param chainId The invalid chainID
    error InvalidChainId(uint256 chainId);

    /// @notice Fills an order on the target chain and transmits a message to the origin chain about the details of the
    /// fulfillment including the orderId and the outputs
    /// @dev This function must call the valid bridge to transmit the orderId, settlementKey, and outputs to the origin chain. This function should revert
    /// if the hash of outputs do not match the outputsHash in they settlement key or if the msg.sender does not match the targetChainFiller in the key.
    /// @param orderId The cross-chain orderId
    /// @param settler The settler contract that holds the settlement, so the bridged message can call finalize on the correct contract.
    /// @param outputs The outputs associated with the corresponding settlement. The outputs MUST be in the same order
    /// as they are in the original order so when hashed they will match the hash in the SettlementKey
    function fillAndTransmitSettlementOutputs(bytes32 orderId, SettlementKey memory key, address settler, OutputToken[] calldata outputs) external;
}
