// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Owned} from "solmate/src/auth/Owned.sol";
import {ResolvedOrder} from "../../../../src/v4/base/ReactorStructs.sol";
import {OutputToken} from "../../../../src/base/ReactorStructs.sol";
import {IProtocolFeeController} from "../../../../src/v4/interfaces/IProtocolFeeController.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

/// @notice Mock protocol fee controller that returns duplicate fee outputs
contract MockFeeControllerDuplicates is IProtocolFeeController, Owned(msg.sender) {
    uint256 private constant BPS = 10000;
    address public immutable feeRecipient;

    constructor(address _feeRecipient) {
        feeRecipient = _feeRecipient;
    }

    mapping(ERC20 tokenIn => mapping(address tokenOut => uint256)) public fees;

    /// @inheritdoc IProtocolFeeController
    function getFeeOutputs(ResolvedOrder memory order) external view override returns (OutputToken[] memory result) {
        result = new OutputToken[](2);

        ERC20 tokenIn = order.input.token;
        address outputToken = order.outputs[0].token;
        uint256 fee = fees[tokenIn][outputToken];
        uint256 feeAmount = order.outputs[0].amount * fee / BPS;

        // Return duplicate fee outputs for the same token
        result[0] = OutputToken({token: outputToken, amount: feeAmount, recipient: feeRecipient});
        result[1] = OutputToken({token: outputToken, amount: feeAmount, recipient: feeRecipient});
    }

    function setFee(ERC20 tokenIn, address tokenOut, uint256 fee) external onlyOwner {
        fees[tokenIn][tokenOut] = fee;
    }
}
