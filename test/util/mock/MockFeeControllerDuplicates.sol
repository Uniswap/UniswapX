// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {Owned} from "solmate/src/auth/Owned.sol";
import {ResolvedOrder, OutputToken} from "../../../src/base/ReactorStructs.sol";
import {IProtocolFeeController} from "../../../src/interfaces/IProtocolFeeController.sol";

/// @notice Mock protocol fee controller
contract MockFeeControllerDuplicates is IProtocolFeeController, Owned(msg.sender) {
    error InvalidFee();

    uint256 private constant BPS = 10000;
    address public immutable feeRecipient;

    constructor(address _feeRecipient) {
        feeRecipient = _feeRecipient;
    }

    mapping(address tokenIn => mapping(address tokenOut => uint256)) public fees;

    /// @inheritdoc IProtocolFeeController
    function getFeeOutputs(ResolvedOrder[] memory orders)
        external
        view
        override
        returns (OutputToken[][] memory result)
    {
        result = new OutputToken[][](orders.length);

        for (uint256 i = 0; i < orders.length; i++) {
            ResolvedOrder memory order = orders[i];
            // use max size for now, one fee per output as overestimate
            OutputToken[] memory feeOutputs = new OutputToken[](order.outputs.length);
            address tokenIn = order.input.token;
            uint256 feeCount;

            for (uint256 j = 0; j < order.outputs.length; j++) {
                address outputToken = order.outputs[j].token;
                uint256 fee = fees[tokenIn][outputToken];
                // TODO: deduplicate
                if (fee != 0) {
                    uint256 feeAmount = order.outputs[j].amount * fee / BPS;

                    feeOutputs[feeCount] = OutputToken({token: outputToken, amount: feeAmount, recipient: feeRecipient});
                    feeCount++;
                }
            }

            assembly {
                // update array size to the actual number of unique fee outputs pairs
                // since the array was initialized with an upper bound of the total number of outputs
                // note: this leaves a few unused memory slots, but free memory pointer
                // still points to the next fresh piece of memory
                mstore(feeOutputs, feeCount)
            }
            result[i] = feeOutputs;
        }
    }

    function setFee(address tokenIn, address tokenOut, uint256 fee) external onlyOwner {
        fees[tokenIn][tokenOut] = fee;
    }
}
