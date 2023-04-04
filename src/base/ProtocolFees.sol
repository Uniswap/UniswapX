// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {CurrencyLibrary} from "../lib/CurrencyLibrary.sol";
import {ResolvedOrder, OutputToken} from "../base/ReactorStructs.sol";

/// @notice Handling for interface-protocol-split fees
abstract contract ProtocolFees {
    error InsufficientProtocolFee();

    /// @dev The number of basis points per whole
    uint256 private constant BPS = 10000;

    address public immutable GOVERNANCE;
    address public immutable PROTOCOL_FEE_RECIPIENT;

    /// @notice stores the fees for each token
    /// @dev maps token address to fee in bps
    mapping(address => uint8) public protocolFees;

    constructor(address _governance, address _protocolFeeRecipient) {
        GOVERNANCE = _governance;
        PROTOCOL_FEE_RECIPIENT = _protocolFeeRecipient;
    }

    function validateProtocolFees(ResolvedOrder memory order) internal {
        uint256 outputsLength = order.outputs.length;
        address[] memory validatedTokens = new address[](outputsLength);
        // Iterate over outputs
        for (uint256 i = 0; i < outputsLength; i++) {
            // Iterate over validatedTokens
            for (uint256 j = 0; j < outputsLength; j++) {
                if (validatedTokens[j] == address(0)) {
                    validateTokensProtocolFee(order.outputs[i].token, order.outputs);
                }
                if (order.outputs[i].token == validatedTokens[j]) {
                    break;
                }
            }
        }
    }

    function validateTokensProtocolFee(address token, OutputToken[] memory outputs) internal view {
        if (protocolFees[token] == 0) {
            return;
        } else {
            uint256 sumAmounts;
            uint256 protocolFeeAmount;
            uint256 outputsLength = outputs.length;
            for (uint256 i = 0; i < outputsLength; i++) {
                if (outputs[i].token == token) {
                    sumAmounts += outputs[i].amount;
                    if (outputs[i].recipient == PROTOCOL_FEE_RECIPIENT) {
                        protocolFeeAmount = outputs[i].amount;
                    }
                }
            }
            if (protocolFeeAmount < (sumAmounts * protocolFees[token] / BPS)) {
                revert InsufficientProtocolFee();
            }
        }
    }
}
