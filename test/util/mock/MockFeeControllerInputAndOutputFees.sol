// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Owned} from "solmate/src/auth/Owned.sol";
import {ResolvedOrder, OutputToken} from "../../../src/base/ReactorStructs.sol";
import {IProtocolFeeController} from "../../../src/interfaces/IProtocolFeeController.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

/// @notice Mock protocol fee controller taking fee on input tokens
contract MockFeeControllerInputAndOutputFees is IProtocolFeeController, Owned(msg.sender) {
    uint256 private constant BPS = 10000;
    address public immutable feeRecipient;

    constructor(address _feeRecipient) {
        feeRecipient = _feeRecipient;
    }

    mapping(ERC20 tokenIn => uint256) public fees;

    /// @inheritdoc IProtocolFeeController
    function getFeeOutputs(ResolvedOrder memory order) external view override returns (OutputToken[] memory result) {
        result = new OutputToken[](2);

        uint256 fee = fees[order.input.token];
        uint256 feeAmount = order.input.amount * fee / BPS;
        result[0] = OutputToken({token: address(order.input.token), amount: feeAmount, recipient: feeRecipient});

        address outputFeeToken = order.outputs[0].token;
        fee = fees[ERC20(outputFeeToken)];
        feeAmount = order.outputs[0].amount * fee / BPS;
        result[1] = OutputToken({token: outputFeeToken, amount: feeAmount, recipient: feeRecipient});
    }

    function setFee(ERC20 tokenIn, uint256 fee) external onlyOwner {
        fees[tokenIn] = fee;
    }
}
