// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IPermitPost, Permit, TokenDetails, TokenType} from "permitpost/interfaces/IPermitPost.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {OrderValidator} from "../lib/OrderValidator.sol";
import {ReactorEvents} from "../lib/ReactorEvents.sol";
import {IReactorCallback} from "../interfaces/IReactorCallback.sol";
import {IReactor} from "../interfaces/IReactor.sol";
import {
    SignedOrder,
    ResolvedOrder,
    OrderInfo,
    OrderStatus,
    TokenAmount,
    Signature,
    Output
} from "../lib/ReactorStructs.sol";

/// @notice Reactor for simple limit orders
abstract contract BaseReactor is IReactor, OrderValidator, ReactorEvents {
    IPermitPost public immutable permitPost;

    constructor(address _permitPost) {
        permitPost = IPermitPost(_permitPost);
    }

    /// @inheritdoc IReactor
    function execute(SignedOrder calldata order, address fillContract, bytes calldata fillData) external override {
        ResolvedOrder[] memory resolvedOrders = new ResolvedOrder[](1);
        resolvedOrders[0] = resolve(order.order);
        bytes32[] memory orderHashes = new bytes32[](1);
        orderHashes[0] = keccak256(order.order);
        Signature[] memory signatures = new Signature[](1);
        signatures[0] = order.sig;

        _fill(resolvedOrders, signatures, orderHashes, fillContract, fillData);
    }

    /// @inheritdoc IReactor
    function executeBatch(SignedOrder[] calldata orders, address fillContract, bytes calldata fillData)
        external
        override
    {
        ResolvedOrder[] memory resolvedOrders = new ResolvedOrder[](orders.length);
        bytes32[] memory orderHashes = new bytes32[](orders.length);
        Signature[] memory signatures = new Signature[](orders.length);
        for (uint256 i = 0; i < orders.length; i++) {
            resolvedOrders[i] = resolve(orders[i].order);
            orderHashes[i] = keccak256(orders[i].order);
            signatures[i] = orders[i].sig;
        }
        _fill(resolvedOrders, signatures, orderHashes, fillContract, fillData);
    }

    /// @notice validates and fills a list of orders, marking it as filled
    function _fill(
        ResolvedOrder[] memory orders,
        Signature[] memory signatures,
        bytes32[] memory orderHashes,
        address fillContract,
        bytes calldata fillData
    ) internal {
        for (uint256 i = 0; i < orders.length; i++) {
            _validateOrderInfo(orders[i].info);
            _updateFilled(orderHashes[i]);
            _transferTokens(orders[i], signatures[i], orderHashes[i], fillContract);
        }

        IReactorCallback(fillContract).reactorCallback(orders, fillData);

        // transfer output tokens to their respective recipients
        for (uint256 i = 0; i < orders.length; i++) {
            for (uint256 j = 0; j < orders[i].outputs.length; j++) {
                Output memory output = orders[i].outputs[j];
                ERC20(output.token).transferFrom(fillContract, output.recipient, output.amount);
            }

            emit Fill(orderHashes[i], msg.sender);
        }
    }

    /// @notice Transfers tokens to the fillContract using permitPost
    function _transferTokens(ResolvedOrder memory order, Signature memory sig, bytes32 orderHash, address fillContract)
        private
    {
        Permit memory permit = Permit(_tokenDetails(order.input), address(this), order.info.deadline, orderHash);
        address[] memory to = new address[](1);
        to[0] = fillContract;

        uint256[] memory ids = new uint256[](1);
        ids[0] = 0;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = order.input.amount;

        address sender = permitPost.unorderedTransferFrom(permit, to, ids, amounts, order.info.nonce, sig);
        if (sender != order.info.offerer) {
            revert InvalidSender();
        }
    }

    /// @notice returns a TokenDetails array of length 1 with the given order input
    function _tokenDetails(TokenAmount memory input) private pure returns (TokenDetails[] memory result) {
        result = new TokenDetails[](1);
        result[0] = TokenDetails(TokenType.ERC20, input.token, input.amount, 0);
    }

    /// @inheritdoc IReactor
    function resolve(bytes calldata order) public view virtual returns (ResolvedOrder memory resolvedOrder);
}
