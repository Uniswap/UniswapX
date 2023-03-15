// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {SettlementInfo, CollateralToken, OutputToken} from "../base/SettlementStructs.sol";
import {InputToken} from "../../base/ReactorStructs.sol";
/// @dev External struct used to specify cross chain limit orders

struct CrossChainLimitOrder {
    // generic order information
    SettlementInfo info;
    // The tokens that the offerer will provide when settling the order
    InputToken input;
    // The collateral the filler must put down while the order is being settled
    CollateralToken fillerCollateral;
    // The collateral the challenger must put down if they challenge an optimistic order
    CollateralToken challengerCollateral;
    // The tokens that must be received to satisfy the order
    OutputToken[] outputs;
}

/// @notice helpers for handling limit order objects
library CrossChainLimitOrderLib {
    bytes private constant OUTPUT_TOKEN_TYPE =
        "OutputToken(address recipient,address token,uint256 amount,uint256 chainId)";
    bytes32 private constant OUTPUT_TOKEN_TYPE_HASH = keccak256(OUTPUT_TOKEN_TYPE);

    bytes internal constant ORDER_TYPE = abi.encodePacked(
        "CrossChainLimitOrder(",
        "address settlerContract,",
        "address offerer,",
        "uint256 nonce,",
        "uint256 initiateDeadline,",
        "uint256 settlementPeriod",
        "address settlementOracle",
        "uint256 validationContract,",
        "uint256 validationData,",
        "address inputToken,",
        "uint256 inputAmount,",
        "address collateralToken,",
        "uint256 collateralAmount,",
        "OutputToken[] outputs)",
        OUTPUT_TOKEN_TYPE
    );
    bytes32 internal constant ORDER_TYPE_HASH = keccak256(ORDER_TYPE);

    string private constant TOKEN_PERMISSIONS_TYPE = "TokenPermissions(address token,uint256 amount)";
    string internal constant PERMIT2_ORDER_TYPE =
        string(abi.encodePacked("CrossChainLimitOrder witness)", ORDER_TYPE, TOKEN_PERMISSIONS_TYPE));

    /// @notice returns the hash of an output token struct
    function hash(OutputToken memory output) private pure returns (bytes32) {
        return
            keccak256(abi.encode(OUTPUT_TOKEN_TYPE_HASH, output.recipient, output.token, output.amount, output.chainId));
    }

    /// @notice returns the hash of an output token struct
    function hash(OutputToken[] memory outputs) private pure returns (bytes32) {
        bytes32[] memory outputHashes = new bytes32[](outputs.length);
        for (uint256 i = 0; i < outputs.length; i++) {
            outputHashes[i] = hash(outputs[i]);
        }
        return keccak256(abi.encodePacked(outputHashes));
    }

    /// @notice hash the given order
    /// @param order the order to hash
    /// @return the eip-712 order hash
    function hash(CrossChainLimitOrder memory order) internal pure returns (bytes32) {
        bytes memory part1 = abi.encode(
            ORDER_TYPE_HASH,
            order.info.settlerContract,
            order.info.offerer,
            order.info.nonce,
            order.info.initiateDeadline,
            order.info.optimisticSettlementPeriod,
            order.info.challengePeriod,
            order.info.settlementOracle,
            order.info.validationContract,
            keccak256(order.info.validationData),
            order.input.token,
            order.input.amount,
            order.fillerCollateral.token,
            order.fillerCollateral.amount
        );

        // avoid stack too deep
        bytes memory part2 =
            abi.encode(order.challengerCollateral.token, order.challengerCollateral.amount, hash(order.outputs));

        return keccak256(abi.encodePacked(part1, part2));
    }
}
