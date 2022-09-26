// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {IPermitPost, Permit, TokenDetails} from "permitpost/interfaces/IPermitPost.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ReactorEvents} from "../base/ReactorEvents.sol";
import {OrderInfoLib} from "../lib/OrderInfoLib.sol";
import {PermitPostLib} from "../lib/PermitPostLib.sol";
import {IReactorCallback} from "../interfaces/IReactorCallback.sol";
import {IReactor} from "../interfaces/IReactor.sol";
import {
    SignedOrder,
    ResolvedOrder,
    OrderInfo,
    InputToken,
    Signature,
    OutputToken,
    InternalOrder
} from "../base/ReactorStructs.sol";

/// @notice Generic reactor logic for settling off-chain signed orders
///     using arbitrary fill methods specified by a taker
abstract contract BaseReactor is IReactor, ReactorEvents {
    using SafeTransferLib for ERC20;
    using PermitPostLib for address;
    using OrderInfoLib for OrderInfo;

    IPermitPost public immutable permitPost;

    constructor(address _permitPost) {
        permitPost = IPermitPost(_permitPost);
    }

    /// @inheritdoc IReactor
    function execute(SignedOrder memory order, address fillContract, bytes calldata fillData) external override {
        SignedOrder[] memory orders = new SignedOrder[](1);
        orders[0] = order;

        executeBatch(orders, fillContract, fillData);
    }

    /// @inheritdoc IReactor
    function executeBatch(SignedOrder[] memory orders, address fillContract, bytes calldata fillData) public override {
        InternalOrder[] memory internalOrders = new InternalOrder[](orders.length);

        unchecked {
            for (uint256 i = 0; i < orders.length; i++) {
                internalOrders[i] = InternalOrder({
                    order: resolve(orders[i].order),
                    sig: orders[i].sig,
                    hash: keccak256(orders[i].order)
                });
            }
        }
        _fill(internalOrders, fillContract, fillData);
    }

    /// @notice validates and fills a list of orders, marking it as filled
    function _fill(InternalOrder[] memory orders, address fillContract, bytes calldata fillData) internal {
        ResolvedOrder[] memory resolvedOrders = new ResolvedOrder[](orders.length);
        unchecked {
            for (uint256 i = 0; i < orders.length; i++) {
                InternalOrder memory order = orders[i];
                order.order.info.validate();
                _transferTokens(order, fillContract);
                resolvedOrders[i] = order.order;
            }
        }

        IReactorCallback(fillContract).reactorCallback(resolvedOrders, msg.sender, fillData);

        unchecked {
            // transfer output tokens to their respective recipients
            for (uint256 i = 0; i < orders.length; i++) {
                ResolvedOrder memory resolvedOrder = orders[i].order;

                for (uint256 j = 0; j < resolvedOrder.outputs.length; j++) {
                    OutputToken memory output = resolvedOrder.outputs[j];
                    ERC20(output.token).safeTransferFrom(fillContract, output.recipient, output.amount);
                }

                emit Fill(orders[i].hash, msg.sender, resolvedOrder.info.nonce, resolvedOrder.info.offerer);
            }
        }
    }

    /// @notice Transfers tokens to the fillContract using permitPost
    function _transferTokens(InternalOrder memory order, address fillContract) private {
        Permit memory permit = Permit({
            tokens: order.order.input.token.toTokenDetails(order.order.input.amount),
            spender: address(this),
            deadline: order.order.info.deadline,
            // Note: PermitPost verifies for us that the user signed over the orderHash
            // using the witness parameter of the permit
            witness: order.hash
        });
        address[] memory to = new address[](1);
        to[0] = fillContract;

        uint256[] memory ids = new uint256[](1);
        ids[0] = 0;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = order.order.input.amount;

        address sender = permitPost.unorderedTransferFrom(permit, to, ids, amounts, order.order.info.nonce, order.sig);
        if (sender != order.order.info.offerer) {
            revert InvalidSender();
        }
    }

    /// @notice Resolve order-type specific requirements into a generic order with the final inputs and outputs.
    /// @param order The encoded order to resolve
    /// @return resolvedOrder generic resolved order of inputs and outputs
    /// @dev should revert on any order-type-specific validation errors
    function resolve(bytes memory order) internal view virtual returns (ResolvedOrder memory resolvedOrder);
}
