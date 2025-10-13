// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Owned} from "solmate/src/auth/Owned.sol";
import {ResolvedOrder} from "../../../../src/v4/base/ReactorStructs.sol";
import {OutputToken} from "../../../../src/base/ReactorStructs.sol";
import {IProtocolFeeController} from "../../../../src/v4/interfaces/IProtocolFeeController.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

/// @notice Mock protocol fee controller
contract MockFeeController is IProtocolFeeController, Owned(msg.sender) {
    uint256 private constant BPS = 10000;
    address public immutable feeRecipient;

    constructor(address _feeRecipient) {
        feeRecipient = _feeRecipient;
    }

    mapping(ERC20 tokenIn => mapping(address tokenOut => uint256)) public fees;

    /// @inheritdoc IProtocolFeeController
    function getFeeOutputs(ResolvedOrder memory order) external view override returns (OutputToken[] memory result) {
        result = new OutputToken[](order.outputs.length);

        // use max size for now, one fee per output as overestimate
        ERC20 tokenIn = order.input.token;
        uint256 feeCount;

        for (uint256 j = 0; j < order.outputs.length; j++) {
            address outputToken = order.outputs[j].token;
            uint256 fee = fees[tokenIn][outputToken];
            if (fee != 0) {
                uint256 feeAmount = order.outputs[j].amount * fee / BPS;

                // check if token already has fee
                bool found;
                for (uint256 k = 0; k < feeCount; k++) {
                    OutputToken memory feeOutput = result[k];
                    if (feeOutput.token == outputToken) {
                        found = true;
                        feeOutput.amount += feeAmount;
                    }
                }

                if (!found && feeAmount > 0) {
                    result[feeCount] = OutputToken({token: outputToken, amount: feeAmount, recipient: feeRecipient});
                    feeCount++;
                }
            }
        }

        assembly {
            // update array size to the actual number of unique fee outputs pairs
            // since the array was initialized with an upper bound of the total number of outputs
            // note: this leaves a few unused memory slots, but free memory pointer
            // still points to the next fresh piece of memory
            mstore(result, feeCount)
        }
    }

    function setFee(ERC20 tokenIn, address tokenOut, uint256 fee) external onlyOwner {
        fees[tokenIn][tokenOut] = fee;
    }
}
