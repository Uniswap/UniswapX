// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {OutputToken} from "../../../../src/xchain-gouda/base/SettlementStructs.sol";
import {SignedOrder} from "../../../../src/base/ReactorStructs.sol";
import {ISettlementOracle} from "../../../../src/xchain-gouda/interfaces/ISettlementOracle.sol";

/// @notice Interface for cross chain listener oracles for cross-chain gouda
contract MockSettlementOracle is ISettlementOracle {
    mapping(bytes32 => OutputToken[]) settlementOutputs;

    function getSettlementInfo(bytes32 orderId, address targetChainFiller)
        external
        view
        returns (OutputToken[] memory filledOutputs)
    {
        return settlementOutputs[keccak256(abi.encode(orderId, targetChainFiller))];
    }

    function logSettlementInfo(bytes32 orderId, address targetChainFiller, OutputToken[] calldata outputs) external {
        OutputToken[] storage settlementInfo = settlementOutputs[keccak256(abi.encode(orderId, targetChainFiller))];
        for (uint256 i = 0; i < outputs.length; i++) {
            settlementInfo.push(outputs[i]);
        }
    }
}
