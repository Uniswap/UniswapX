// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {InputToken, OutputToken} from "../../base/ReactorStructs.sol";
import {OrderInfo} from "../base/ReactorStructs.sol";
import {OrderInfoLib} from "./OrderInfoLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {PriceCurveLib, PriceCurveElement} from "lib/tribunal/src/lib/PriceCurveLib.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

/// @notice Cosigner data for hybrid auction orders
struct HybridCosignerData {
    uint256 auctionTargetBlock;
    uint256[] supplementalPriceCurve;
}

/// @notice Input tokens for hybrid auction
/// @dev if exact-in, scale down from maxAmount
/// @dev if exact-out, input amount is fixed at maxAmount
struct HybridInput {
    ERC20 token;
    uint256 maxAmount;
}

/// @notice Output tokens for hybrid auction
/// @dev if exact-in, scale up from minAmount
/// @dev if exact-out, output amount is fixed at minAmount
struct HybridOutput {
    address token;
    uint256 minAmount;
    address recipient;
}

/// @notice Hybrid auction order combining Dutch decay and priority gas auctions
struct HybridOrder {
    OrderInfo info;
    address cosigner;
    HybridInput input;
    HybridOutput[] outputs;
    uint256 auctionStartBlock;
    uint256 baselinePriorityFee;
    uint256 scalingFactor;
    uint256[] priceCurve;
    HybridCosignerData cosignerData;
    bytes cosignature;
}

/// @notice Library for handling hybrid auction orders
library HybridOrderLib {
    using OrderInfoLib for OrderInfo;
    using FixedPointMathLib for uint256;
    using PriceCurveLib for uint256[];
    using PriceCurveLib for uint256;

    error InvalidTargetBlock(uint256 blockNumber, uint256 targetBlockNumber);
    error InvalidTargetBlockDesignation();

    bytes internal constant HYBRID_ORDER_TYPE = abi.encodePacked(
        "HybridOrder(",
        "OrderInfo info,",
        "address cosigner,",
        "HybridInput input,",
        "HybridOutput[] outputs,",
        "uint256 auctionTargetBlock,",
        "uint256 baselinePriorityFee,",
        "uint256 scalingFactor,",
        "uint256[] priceCurve)"
    );
    // Note: cosignerData and cosignature are not included in EIP-712 type hash

    bytes internal constant HYBRID_INPUT_TYPE = abi.encodePacked("HybridInput(", "address token,", "uint256 maxAmount)");

    bytes internal constant HYBRID_OUTPUT_TYPE =
        abi.encodePacked("HybridOutput(", "address token,", "uint256 minAmount,", "address recipient)");

    bytes internal constant ORDER_INFO_TYPE = abi.encodePacked(
        "OrderInfo(",
        "address reactor,",
        "address swapper,",
        "uint256 nonce,",
        "uint256 deadline,",
        "address preExecutionHook,",
        "bytes preExecutionHookData,",
        "address postExecutionHook,",
        "bytes postExecutionHookData,",
        "address auctionResolver)"
    );

    bytes internal constant TOKEN_PERMISSIONS_TYPE = "TokenPermissions(address token,uint256 amount)";

    bytes32 internal constant HYBRID_INPUT_TYPE_HASH = keccak256(HYBRID_INPUT_TYPE);
    bytes32 internal constant HYBRID_OUTPUT_TYPE_HASH = keccak256(HYBRID_OUTPUT_TYPE);
    bytes32 internal constant ORDER_INFO_TYPE_HASH = keccak256(ORDER_INFO_TYPE);

    bytes32 internal constant HYBRID_ORDER_TYPE_HASH =
        keccak256(abi.encodePacked(HYBRID_ORDER_TYPE, HYBRID_INPUT_TYPE, HYBRID_OUTPUT_TYPE, ORDER_INFO_TYPE));

    // Note: Sub-structs must be defined in alphabetical order in the EIP-712 spec
    string internal constant PERMIT2_ORDER_TYPE = string(
        abi.encodePacked(
            "HybridOrder witness)",
            HYBRID_INPUT_TYPE,
            HYBRID_ORDER_TYPE,
            HYBRID_OUTPUT_TYPE,
            ORDER_INFO_TYPE,
            TOKEN_PERMISSIONS_TYPE
        )
    );

    /// @notice Hash a hybrid order
    function hash(HybridOrder memory order) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                HYBRID_ORDER_TYPE_HASH,
                order.info.hash(),
                order.cosigner,
                hashInput(order.input),
                hashOutputs(order.outputs),
                order.auctionStartBlock,
                order.baselinePriorityFee,
                order.scalingFactor,
                keccak256(abi.encodePacked(order.priceCurve))
            )
        );
    }

    /// @notice Hash hybrid input
    function hashInput(HybridInput memory input) private pure returns (bytes32) {
        return keccak256(abi.encode(HYBRID_INPUT_TYPE_HASH, input.token, input.maxAmount));
    }

    /// @notice Hash hybrid outputs
    function hashOutputs(HybridOutput[] memory outputs) private pure returns (bytes32) {
        bytes32[] memory hashes = new bytes32[](outputs.length);
        for (uint256 i = 0; i < outputs.length; i++) {
            hashes[i] = keccak256(
                abi.encode(HYBRID_OUTPUT_TYPE_HASH, outputs[i].token, outputs[i].minAmount, outputs[i].recipient)
            );
        }
        return keccak256(abi.encodePacked(hashes));
    }

    /// @notice get the digest of the cosigner data
    /// @param order the hybridOrder
    /// @param orderHash the hash of the order
    function cosignerDigest(HybridOrder memory order, bytes32 orderHash) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(orderHash, block.chainid, abi.encode(order.cosignerData)));
    }

    /// @notice Derive scaling factor for the current block for the hybrid auction
    /// @dev Adapted from Tribunal's deriveAmounts to work with UniswapX HybridOrder structure
    /// @param order The hybrid order containing all auction parameters
    /// @param priceCurve The effective price curve to use
    /// @param targetBlock The target block for the auction start
    /// @param fillBlock The block at which the fill is happening
    /// @return currentScalingFactor The current scaling factor
    function deriveCurrentScalingFactor(
        HybridOrder memory order,
        uint256[] memory priceCurve,
        uint256 targetBlock,
        uint256 fillBlock
    ) internal pure returns (uint256 currentScalingFactor) {
        currentScalingFactor = 1e18;

        // Calculate scaling from price curve if auction is active
        if (targetBlock != 0) {
            if (targetBlock > fillBlock) {
                revert InvalidTargetBlock(targetBlock, fillBlock);
            }
            // Derive the total blocks passed since the target block.
            uint256 blocksPassed;
            unchecked {
                blocksPassed = fillBlock - targetBlock;
            }
            currentScalingFactor = priceCurve.getCalculatedValues(blocksPassed);
        } else {
            if (priceCurve.length != 0) {
                revert InvalidTargetBlockDesignation();
            }
        }

        if (!order.scalingFactor.sharesScalingDirection(currentScalingFactor)) {
            revert PriceCurveLib.InvalidPriceCurveParameters();
        }
    }

    /// @notice scale the outputs of a hybrid order for exact-in orders
    /// @param outputs the outputs to scale
    /// @param scalingFactor the scaling factor to use
    /// @return outputs scaled up from minAmount
    function scale(HybridOutput[] memory outputs, uint256 scalingFactor) internal pure returns (OutputToken[] memory) {
        OutputToken[] memory result = new OutputToken[](outputs.length);
        for (uint256 i = 0; i < outputs.length; i++) {
            result[i] = OutputToken({
                token: outputs[i].token,
                amount: outputs[i].minAmount.mulWadUp(scalingFactor),
                recipient: outputs[i].recipient
            });
        }
        return result;
    }

    /// @notice scale the input of a hybrid order for exact-in orders
    /// @param input the input to scale
    /// @param scalingFactor the scaling factor to use
    /// @return input scaled down from maxAmount
    function scale(HybridInput memory input, uint256 scalingFactor) internal pure returns (InputToken memory) {
        return
            InputToken({token: input.token, amount: input.maxAmount.mulWad(scalingFactor), maxAmount: input.maxAmount});
    }
}
