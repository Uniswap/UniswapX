// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ISettlementFiller} from "../interfaces/ISettlementFiller.sol";
import {OutputToken} from "../base/SettlementStructs.sol";
import {ResolvedOrderLib} from "../lib/ResolvedOrderLib.sol";

/// @notice Generic cross-chain filler logic for filling an order on the target chain
abstract contract BaseSettlementFiller is ISettlementFiller {
    using SafeTransferLib for ERC20;

    /// @notice Thrown when output token does not match the chain id of this deployed contract
    /// @param chainId The invalid chainID
    error InvalidChainId(uint256 chainId);

    function fillAndTransmitSettlementOutputs(bytes32 orderId, OutputToken[] calldata outputs) external {
        unchecked {
            for (uint256 i = 0; i < outputs.length; i++) {
                OutputToken memory output = outputs[i];
                if (output.chainId == block.chainid) revert InvalidChainId(output.chainId);
                ERC20(output.token).safeTransferFrom(msg.sender, output.recipient, output.amount);
            }
            transmitSettlementOutputs(keccak256(abi.encode(orderId, msg.sender)), outputs);
        }
    }

    function transmitSettlementOutputs(bytes32 settlementId, OutputToken[] calldata outputs) internal virtual;
}
