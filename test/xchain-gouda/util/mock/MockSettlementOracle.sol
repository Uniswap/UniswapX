// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {OutputToken} from "../../../../src/xchain-gouda/base/SettlementStructs.sol";
import {SignedOrder} from "../../../../src/base/ReactorStructs.sol";
import {ISettlementOracle} from "../../../../src/xchain-gouda/interfaces/ISettlementOracle.sol";

/// @notice Interface for cross chain listener oracles for cross-chain gouda
contract MockSettlementOracle is ISettlementOracle {
    struct FillInfo {
        OutputToken[] outputs;
        uint256 timestamp;
    }

    mapping(bytes32 => FillInfo) settlementOutputs;

    function getSettlementInfo(bytes32 orderId, address targetChainFiller)
        external
        view
        returns (OutputToken[] memory filledOutputs, uint256 fillTimestamp)
    {
        FillInfo memory settlement = settlementOutputs[keccak256(abi.encode(orderId, targetChainFiller))];
        return (settlement.outputs, settlement.timestamp);
    }

    function logSettlementInfo(
        bytes32 orderId,
        address targetChainFiller,
        uint256 fillTimestamp,
        OutputToken[] calldata outputs
    ) external {
        FillInfo storage settlementInfo = settlementOutputs[keccak256(abi.encode(orderId, targetChainFiller))];
        settlementInfo.timestamp = fillTimestamp;
        for (uint256 i = 0; i < outputs.length; i++) {
            settlementInfo.outputs.push(outputs[i]);
        }
    }
}
