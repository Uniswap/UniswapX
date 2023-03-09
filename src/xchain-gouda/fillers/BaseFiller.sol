// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ISettlementFiller} from "../interfaces/ISettlementFiller.sol";
import {OutputToken, SettlementKey} from "../base/SettlementStructs.sol";
import {ResolvedOrderLib} from "../lib/ResolvedOrderLib.sol";

/// @notice Generic cross-chain filler logic for filling an order on the target chain
abstract contract BaseSettlementFiller is ISettlementFiller {
    using SafeTransferLib for ERC20;

    function fillAndTransmitSettlement(
        bytes32 orderId,
        SettlementKey memory key,
        address settler,
        OutputToken[] calldata outputs
    ) external {
        if (keccak256(abi.encode(outputs)) != key.outputsHash) revert InvalidOutputsHash();
        if (block.timestamp > key.fillDeadline) revert FillDeadlineMissed();

        unchecked {
            for (uint256 i = 0; i < outputs.length; i++) {
                OutputToken memory output = outputs[i];
                if (output.chainId != block.chainid) revert InvalidChainId(output.chainId);
                ERC20(output.token).safeTransferFrom(msg.sender, output.recipient, output.amount);
            }
            transmitSettlement(orderId, key, settler, block.timestamp);
        }
    }

    function transmitSettlement(bytes32 orderId, SettlementKey memory key, address settler, uint256 fillTimestamp)
        internal
        virtual;
}
