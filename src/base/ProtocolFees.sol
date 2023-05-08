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

    /// @dev The address of the fee controller
    IProtocolFeeController public feeController;

    constructor(address _owner) Owned(_owner) {}

    /// @notice Takes fees from the orders
    /// @dev modifies the orders to include protocol fee outputs
    /// @param order The encoded order to take fees from
    function _takeFees(ResolvedOrder memory order) internal view {
        if (address(feeController) == address(0)) {
            return;
        }

        OutputToken[] memory feeOutputs = feeController.getFeeOutputs(order);
        uint256 outputsLength = order.outputs.length;
        uint256 feeOutputsLength = feeOutputs.length;

        // apply fee outputs
        // fill new outputs with old outputs
        OutputToken[] memory newOutputs = new OutputToken[](
            outputsLength + feeOutputsLength
        );
        for (uint256 j = 0; j < outputsLength; j++) {
            newOutputs[j] = order.outputs[j];
        }

        for (uint256 j = 0; j < feeOutputs.length; j++) {
            OutputToken memory feeOutput = feeOutputs[j];
            // assert no duplicates
            for (uint256 k = 0; k < j; k++) {
                if (feeOutput.token == feeOutputs[k].token) {
                    revert DuplicateFeeOutput();
                }
            }

            // assert not greater than MAX_FEE_BPS
            uint256 tokenValue;
            for (uint256 k = 0; k < outputsLength; k++) {
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
            newOutputs[outputsLength + j] = feeOutput;
        }

        order.outputs = newOutputs;
    }

    /// @notice sets the protocol fee controller
    /// @dev only callable by the owner
    /// @param _feeController the new fee controller
    function setProtocolFeeController(address _feeController) external onlyOwner {
        feeController = IProtocolFeeController(_feeController);
    }
}
