// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IPermitPost, Permit, TokenDetails, TokenType} from "permitpost/interfaces/IPermitPost.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {OrderValidator} from "../lib/OrderValidator.sol";
import {ReactorEvents} from "../lib/ReactorEvents.sol";
import {IReactorCallback} from "../interfaces/IReactorCallback.sol";
import {ResolvedOrder, OrderInfo, TokenAmount, Signature, Output} from "../lib/ReactorStructs.sol";

/// @notice Reactor for simple limit orders
contract BaseReactor is OrderValidator, ReactorEvents {
    address public immutable permitPost;

    constructor(address _permitPost) {
        permitPost = _permitPost;
    }

    /// @notice validates and fills an order, marking it as filled
    function _fill(
        ResolvedOrder memory order,
        Signature calldata sig,
        bytes32 orderHash,
        address fillContract,
        bytes calldata fillData
    )
        internal
    {
        _validate(order.info);

        _transferTokens(order, orderHash, fillContract, sig);

        ResolvedOrder[] memory resolvedOrders = new ResolvedOrder[](1);
        resolvedOrders[0] = order;
        IReactorCallback(fillContract).reactorCallback(resolvedOrders, fillData);

        // transfer output tokens to their respective recipients
        for (uint256 i = 0; i < order.outputs.length; i++) {
            Output memory output = order.outputs[i];
            ERC20(output.token).transferFrom(fillContract, output.recipient, output.amount);
        }

        emit Fill(orderHash, msg.sender);
    }

    /// @notice Transfers tokens to the fillContract using permitPost
    function _transferTokens(
        ResolvedOrder memory order,
        bytes32 orderHash,
        address fillContract,
        Signature calldata sig
    )
        private
    {
        Permit memory permit = Permit(_tokenDetails(order.input), address(this), order.info.deadline, orderHash);
        address[] memory to = new address[](1);
        to[0] = fillContract;

        uint256[] memory ids = new uint256[](1);
        ids[0] = 0;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = order.input.amount;

        IPermitPost(permitPost).unorderedTransferFrom(
            permit, order.info.offerer, to, ids, amounts, order.info.nonce, sig
        );
    }

    /// @notice returns a TokenDetails array of length 1 with the given order input
    function _tokenDetails(TokenAmount memory input) private pure returns (TokenDetails[] memory result) {
        result = new TokenDetails[](1);
        result[0] = TokenDetails(TokenType.ERC20, input.token, input.amount, 0);
    }
}
