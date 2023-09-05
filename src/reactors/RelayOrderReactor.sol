// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/security/ReentrancyGuard.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ReactorEvents} from "../base/ReactorEvents.sol";
import {CurrencyLibrary, NATIVE} from "../lib/CurrencyLibrary.sol";
import {IReactorCallback} from "../interfaces/IReactorCallback.sol";
import {IReactor} from "../interfaces/IReactor.sol";
import {ProtocolFees} from "../base/ProtocolFees.sol";
import {Permit2Lib} from "../lib/Permit2Lib.sol";
import {AdvancedOrderLib, AdvancedOrder, ActionType} from "../lib/AdvancedOrderLib.sol";
import {ResolvedAdvancedOrderLib} from "../lib/ResolvedAdvancedOrderLib.sol";
import {
    SignedOrder,
    ResolvedAdvancedOrder,
    OrderInfo,
    InputTokenWithRecipient,
    OutputToken
} from "../base/ReactorStructs.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";

/// @notice Reactor for simple limit orders
contract AdvancedOrderReactor is ReactorEvents, ProtocolFees, ReentrancyGuard {
    using SafeTransferLib for ERC20;
    using CurrencyLibrary for address;
    using Permit2Lib for ResolvedAdvancedOrder;
    using ResolvedAdvancedOrderLib for ResolvedAdvancedOrder;
    using AdvancedOrderLib for AdvancedOrder;

    // Occurs when an output = ETH and the reactor does contain enough ETH but
    // the direct filler did not include enough ETH in their call to execute/executeBatch
    error InsufficientEth();

    /// @notice permit2 address used for token transfers and signature verification
    IPermit2 public immutable permit2;

    address public immutable universalRouter;

    constructor(IPermit2 _permit2, address _protocolFeeOwner, address _universalRouter)
        ProtocolFees(_protocolFeeOwner)
    {
        permit2 = _permit2;
        universalRouter = _universalRouter;
    }

    function execute(SignedOrder calldata order) external payable nonReentrant {
        ResolvedAdvancedOrder[] memory resolvedOrders = new ResolvedAdvancedOrder[](1);
        resolvedOrders[0] = resolve(order);

        _prepare(resolvedOrders);
        _execute(resolvedOrders);
        _fill(resolvedOrders);
    }

    function executeBatch(SignedOrder[] calldata orders) external payable nonReentrant {
        uint256 ordersLength = orders.length;
        ResolvedAdvancedOrder[] memory resolvedOrders = new ResolvedAdvancedOrder[](ordersLength);

        unchecked {
            for (uint256 i = 0; i < ordersLength; i++) {
                resolvedOrders[i] = resolve(orders[i]);
            }
        }

        _prepare(resolvedOrders);
        _execute(resolvedOrders);
        _fill(resolvedOrders);
    }

    function _execute(ResolvedAdvancedOrder[] memory orders) internal {
        uint256 ordersLength = orders.length;
        // actions are encodResolved as (enum actionType, bytes actionData)[]
        for (uint256 i = 0; i < ordersLength; i++) {
            ResolvedAdvancedOrder memory order = orders[i];
            uint256 actionsLength = order.actions.length;

            for (uint256 j = 0; j < actionsLength; j++) {
                (ActionType actionType, bytes memory actionData) = abi.decode(order.actions[j], (ActionType, bytes));
                if (actionType == ActionType.Approve) {
                    (address token) = abi.decode(actionData, (address));
                    // make approval to permit2 if needed
                    require(token != address(0), "invalid token address");
                    if (ERC20(token).allowance(address(this), address(permit2)) == 0) {
                        ERC20(token).approve(address(permit2), type(uint256).max);
                    }
                    permit2.approve(token, universalRouter, type(uint160).max, type(uint48).max);
                }
                else if (actionType == ActionType.UniversalRouter) {
                    /// @dev to use universal router integration, this contract must be recipient of all output tokens
                    (bool success,) = universalRouter.call(actionData);
                    require(success, "call failed");
                }
                else {
                    revert("invalid action type");
                }
            }
        }
    }

    /// @notice validates, injects fees, and transfers input tokens in preparation for order fill
    /// @param orders The orders to prepare
    function _prepare(ResolvedAdvancedOrder[] memory orders) internal {
        uint256 ordersLength = orders.length;
        unchecked {
            for (uint256 i = 0; i < ordersLength; i++) {
                ResolvedAdvancedOrder memory order = orders[i];
                // _injectFees(order);
                order.validate(msg.sender);

                // Since relay order inputs specify recipients, we don't pass into transferInputTokens
                transferInputTokens(order);
            }
        }
    }

    /// @notice fills a list of orders, ensuring all outputs are satisfied
    /// @param orders The orders to fill
    function _fill(ResolvedAdvancedOrder[] memory orders) internal {
        uint256 ordersLength = orders.length;
        // attempt to transfer all currencies to all recipients
        unchecked {
            // transfer output tokens to their respective recipients
            for (uint256 i = 0; i < ordersLength; i++) {
                ResolvedAdvancedOrder memory resolvedOrder = orders[i];
                uint256 outputsLength = resolvedOrder.outputs.length;
                for (uint256 j = 0; j < outputsLength; j++) {
                    OutputToken memory output = resolvedOrder.outputs[j];
                    output.token.transferFillFromBalance(output.recipient, output.amount);
                }

                emit Fill(orders[i].hash, msg.sender, resolvedOrder.info.swapper, resolvedOrder.info.nonce);
            }
        }

        // refund any remaining ETH to the filler. Only occurs when filler sends more ETH than required to
        // `execute()` or `executeBatch()`, or when there is excess contract balance remaining from others
        // incorrectly calling execute/executeBatch without direct filler method but with a msg.value
        if (address(this).balance > 0) {
            CurrencyLibrary.transferNative(msg.sender, address(this).balance);
        }
    }

    receive() external payable {
        // receive native asset to support native output
    }

    function resolve(SignedOrder calldata signedOrder)
        internal
        pure
        returns (ResolvedAdvancedOrder memory resolvedOrder)
    {
        AdvancedOrder memory order = abi.decode(signedOrder.order, (AdvancedOrder));
        _validateOrder(order);

        resolvedOrder = ResolvedAdvancedOrder({
            info: order.info,
            // optionally put actions into wrapped structs
            actions: order.actions,
            inputs: order.inputs,
            outputs: order.outputs,
            sig: signedOrder.sig,
            hash: order.hash()
        });
    }

    function transferInputTokens(ResolvedAdvancedOrder memory order) internal {
        permit2.permitWitnessTransferFrom(
            order.toPermit(),
            order.transferDetails(),
            order.info.swapper,
            order.hash,
            AdvancedOrderLib.PERMIT2_ORDER_TYPE,
            order.sig
        );
    }

    /// @notice validate the relay order fields
    /// @dev Throws if the order is invalid
    function _validateOrder(AdvancedOrder memory order) internal pure {
        // assert that actions are valid and allowed, that calldata is well formed, etc.
    }
}
