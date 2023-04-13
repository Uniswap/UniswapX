// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {Owned} from "solmate/src/auth/Owned.sol";
import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IProtocolFeeController} from "../interfaces/IProtocolFeeController.sol";
import {CurrencyLibrary} from "../lib/CurrencyLibrary.sol";
import {ResolvedOrder, OutputToken} from "../base/ReactorStructs.sol";

/// @notice Handling for protocol fees
abstract contract ProtocolFees is Owned {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;
    using CurrencyLibrary for address;

    error DuplicateFeeOutput();
    error FeeTooLarge();
    error InvalidFeeToken();

    uint256 private constant BPS = 10_000;
    uint256 private constant MAX_FEE_BPS = 5;

    /// @dev The fee recipient used in feesOwed for protocol fees
    address private constant PROTOCOL_FEE_RECIPIENT_STORED = address(0);

    /// @dev The address who can set fee controller
    IProtocolFeeController public feeController;

    constructor(address _owner) Owned(_owner) {}

    /// @notice Takes fees from the orders
    /// @dev modifies the orders to include protocol fee outputs
    /// @param orders The encoded order to take fees from
    function _takeFees(ResolvedOrder[] memory orders) internal view {
        if (address(feeController) == address(0)) {
            return;
        }

        OutputToken[][] memory feeOutputs = feeController.getFeeOutputs(orders);
        require(feeOutputs.length == orders.length, "Invalid fee outputs");

        // apply fee outputs
        for (uint256 i = 0; i < orders.length; i++) {
            ResolvedOrder memory order = orders[i];
            OutputToken[] memory orderFeeOutputs = feeOutputs[i];
            // fill new outputs with old outputs
            OutputToken[] memory newOutputs = new OutputToken[](
                order.outputs.length + orderFeeOutputs.length
            );
            for (uint256 j = 0; j < order.outputs.length; j++) {
                newOutputs[j] = order.outputs[j];
            }

            for (uint256 j = 0; j < orderFeeOutputs.length; j++) {
                OutputToken memory feeOutput = orderFeeOutputs[j];
                // assert no duplicates
                for (uint256 k = 0; k < j; k++) {
                    if (feeOutput.token == orderFeeOutputs[k].token) {
                        revert DuplicateFeeOutput();
                    }
                }

                // assert not greater than MAX_FEE_BPS
                uint256 tokenValue;
                for (uint256 k = 0; k < order.outputs.length; k++) {
                    OutputToken memory output = order.outputs[k];
                    if (output.token == feeOutput.token) {
                        tokenValue += output.amount;
                    }
                }

                // allow fee on input token as well
                if (order.input.token == feeOutput.token) {
                    tokenValue += order.input.amount;
                }

                if (tokenValue == 0) revert InvalidFeeToken();

                if (feeOutput.amount > tokenValue.mulDivDown(MAX_FEE_BPS, BPS)) revert FeeTooLarge();
                newOutputs[order.outputs.length + j] = feeOutput;
            }

            order.outputs = newOutputs;
        }
    }

    /// @notice sets the protocol fee controller
    /// @dev only callable by the owner
    /// @param _feeController the new fee recipient
    function setProtocolFeeController(address _feeController) external onlyOwner {
        feeController = IProtocolFeeController(_feeController);
    }
}
