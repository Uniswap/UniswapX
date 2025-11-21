// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Owned} from "solmate/src/auth/Owned.sol";
import {ResolvedOrder} from "../../../../src/v4/base/ReactorStructs.sol";
import {OutputToken} from "../../../../src/base/ReactorStructs.sol";
import {IProtocolFeeController} from "../../../../src/v4/interfaces/IProtocolFeeController.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";

/// @notice Mock protocol fee controller taking fee on both input and output tokens
contract MockFeeControllerInputAndOutputFees is IProtocolFeeController, Owned(msg.sender) {
    uint256 private constant BPS = 10000;
    address public immutable feeRecipient;

    constructor(address _feeRecipient) {
        feeRecipient = _feeRecipient;
    }

    mapping(ERC20 token => uint256) public fees;

    /// @inheritdoc IProtocolFeeController
    function getFeeOutputs(ResolvedOrder memory order) external view override returns (OutputToken[] memory result) {
        result = new OutputToken[](2);

        uint256 inputFee = fees[order.input.token];
        uint256 inputFeeAmount = order.input.amount * inputFee / BPS;
        result[0] = OutputToken({token: address(order.input.token), amount: inputFeeAmount, recipient: feeRecipient});

        uint256 outputFee = fees[ERC20(order.outputs[0].token)];
        uint256 outputFeeAmount = order.outputs[0].amount * outputFee / BPS;
        result[1] =
            OutputToken({token: address(order.outputs[0].token), amount: outputFeeAmount, recipient: feeRecipient});
    }

    function setFee(ERC20 token, uint256 fee) external onlyOwner {
        fees[token] = fee;
    }
}
