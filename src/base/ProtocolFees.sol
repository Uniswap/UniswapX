// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

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

    /// @notice thrown if two fee outputs have the same token
    error DuplicateFeeOutput(address duplicateToken);
    /// @notice thrown if a given fee output is greater than MAX_FEE_BPS of the order outputs
    error FeeTooLarge(address token, uint256 amount, address recipient);
    /// @notice thrown if a fee output token does not have a corresponding non-fee output
    error InvalidFeeToken(address feeToken);
    /// @notice thrown if fees are taken on both inputs and outputs
    error InputAndOutputFees();

    event ProtocolFeeControllerSet(address oldFeeController, address newFeeController);

    uint256 private constant BPS = 10_000;
    uint256 private constant MAX_FEE_BPS = 5;

    /// @dev The address of the fee controller
    IProtocolFeeController public feeController;

    // @notice Required to customize owner from constructor of BaseReactor.sol
    constructor(address _owner) Owned(_owner) {}

    /// @notice Injects fees into an order
    /// @dev modifies the orders to include protocol fee outputs
    /// @param order The encoded order to inject fees into
    function _injectFees(ResolvedOrder memory order) internal view {
        if (address(feeController) == address(0)) {
            return;
        }

        OutputToken[] memory feeOutputs = feeController.getFeeOutputs(order);
        uint256 outputsLength = order.outputs.length;
        uint256 feeOutputsLength = feeOutputs.length;

        // apply fee outputs
        // fill new outputs with old outputs
        OutputToken[] memory newOutputs = new OutputToken[](outputsLength + feeOutputsLength);

        for (uint256 i = 0; i < outputsLength; i++) {
            newOutputs[i] = order.outputs[i];
        }

        bool outputFeeTaken = false;
        bool inputFeeTaken = false;
        for (uint256 i = 0; i < feeOutputsLength; i++) {
            OutputToken memory feeOutput = feeOutputs[i];
            // assert no duplicates
            for (uint256 j = 0; j < i; j++) {
                if (feeOutput.token == feeOutputs[j].token) {
                    revert DuplicateFeeOutput(feeOutput.token);
                }
            }

            // assert not greater than MAX_FEE_BPS
            uint256 tokenValue;
            for (uint256 j = 0; j < outputsLength; j++) {
                OutputToken memory output = order.outputs[j];
                if (output.token == feeOutput.token) {
                    if (inputFeeTaken) revert InputAndOutputFees();
                    tokenValue += output.amount;
                    outputFeeTaken = true;
                }
            }

            // allow fee on input token as well
            if (address(order.input.token) == feeOutput.token) {
                if (outputFeeTaken) revert InputAndOutputFees();
                tokenValue += order.input.amount;
                inputFeeTaken = true;
            }

            if (tokenValue == 0) revert InvalidFeeToken(feeOutput.token);

            if (feeOutput.amount > tokenValue.mulDivDown(MAX_FEE_BPS, BPS)) {
                revert FeeTooLarge(feeOutput.token, feeOutput.amount, feeOutput.recipient);
            }
            unchecked {
                newOutputs[outputsLength + i] = feeOutput;
            }
        }

        order.outputs = newOutputs;
    }

    /// @notice sets the protocol fee controller
    /// @dev only callable by the owner
    /// @param _newFeeController the new fee controller
    function setProtocolFeeController(address _newFeeController) external onlyOwner {
        address oldFeeController = address(feeController);
        feeController = IProtocolFeeController(_newFeeController);
        emit ProtocolFeeControllerSet(oldFeeController, _newFeeController);
    }
}
