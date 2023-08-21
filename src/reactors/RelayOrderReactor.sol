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
import {RelayOrderLib, RelayOrder} from "../lib/RelayOrderLib.sol";
import {ResolvedRelayOrderLib} from "../lib/ResolvedRelayOrderLib.sol";
import {SignedOrder, ResolvedRelayOrder, OrderInfo, InputToken, OutputToken} from "../base/ReactorStructs.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";

/// @notice Reactor for simple limit orders
contract RelayOrderReactor is IReactor, ReactorEvents, ProtocolFees, ReentrancyGuard {
    using SafeTransferLib for ERC20;
    using CurrencyLibrary for address;
    using Permit2Lib for ResolvedRelayOrder;
    using ResolvedRelayOrderLib for ResolvedRelayOrder;
    using RelayOrderLib for RelayOrder;

    // Occurs when an output = ETH and the reactor does contain enough ETH but
    // the direct filler did not include enough ETH in their call to execute/executeBatch
    error InsufficientEth();

    /// @notice permit2 address used for token transfers and signature verification
    IPermit2 public immutable permit2;

    constructor(IPermit2 _permit2, address _protocolFeeOwner) ProtocolFees(_protocolFeeOwner) {
        permit2 = _permit2;
    }

    /// @inheritdoc IReactor
    function execute(SignedOrder calldata order) external payable nonReentrant {
        ResolvedRelayOrder[] memory resolvedOrders = new ResolvedRelayOrder[](1);
        resolvedOrders[0] = resolve(order);

        _prepare(resolvedOrders);
        _fill(resolvedOrders);
    }

    /// @inheritdoc IReactor
    function executeWithCallback(SignedOrder calldata order, bytes calldata callbackData)
        external
        payable
        nonReentrant
    {
        ResolvedRelayOrder[] memory resolvedOrders = new ResolvedRelayOrder[](1);
        resolvedOrders[0] = resolve(order);

        _prepare(resolvedOrders);
        // TODO: external call logic here
        _fill(resolvedOrders);
    }

    /// @inheritdoc IReactor
    function executeBatch(SignedOrder[] calldata orders) external payable nonReentrant {
        uint256 ordersLength = orders.length;
        ResolvedRelayOrder[] memory resolvedOrders = new ResolvedRelayOrder[](ordersLength);

        unchecked {
            for (uint256 i = 0; i < ordersLength; i++) {
                resolvedOrders[i] = resolve(orders[i]);
            }
        }

        _prepare(resolvedOrders);
        _fill(resolvedOrders);
    }

    /// @inheritdoc IReactor
    function executeBatchWithCallback(SignedOrder[] calldata orders, bytes calldata callbackData)
        external
        payable
        nonReentrant
    {
        uint256 ordersLength = orders.length;
        ResolvedRelayOrder[] memory resolvedOrders = new ResolvedRelayOrder[](ordersLength);

        unchecked {
            for (uint256 i = 0; i < ordersLength; i++) {
                resolvedOrders[i] = resolve(orders[i]);
            }
        }

        _prepare(resolvedOrders);
        // TODO: external call logic here
        _fill(resolvedOrders);
    }

    /// @notice validates, injects fees, and transfers input tokens in preparation for order fill
    /// @param orders The orders to prepare
    function _prepare(ResolvedRelayOrder[] memory orders) internal {
        uint256 ordersLength = orders.length;
        unchecked {
            for (uint256 i = 0; i < ordersLength; i++) {
                ResolvedRelayOrder memory order = orders[i];
                // _injectFees(order);
                order.validate(msg.sender);
                transferInputTokens(order, msg.sender);
            }
        }
    }

    /// @notice fills a list of orders, ensuring all outputs are satisfied
    /// @param orders The orders to fill
    function _fill(ResolvedRelayOrder[] memory orders) internal {
        uint256 ordersLength = orders.length;
        // attempt to transfer all currencies to all recipients
        unchecked {
            // transfer output tokens to their respective recipients
            for (uint256 i = 0; i < ordersLength; i++) {
                ResolvedRelayOrder memory resolvedOrder = orders[i];
                uint256 outputsLength = resolvedOrder.outputs.length;
                for (uint256 j = 0; j < outputsLength; j++) {
                    OutputToken memory output = resolvedOrder.outputs[j];
                    output.token.transferFill(output.recipient, output.amount);
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
        returns (ResolvedRelayOrder memory resolvedOrder)
    {
        RelayOrder memory order = abi.decode(signedOrder.order, (RelayOrder));
        _validateOrder(order);

        resolvedOrder = ResolvedRelayOrder({
            info: order.info,
            // optionally put actions into wrapped structs
            actions: order.actions,
            inputs: order.inputs,
            outputs: order.outputs,
            sig: signedOrder.sig,
            hash: order.hash()
        });
    }

    function transferInputTokens(ResolvedRelayOrder memory order, address to) internal {
        permit2.permitWitnessTransferFrom(
            order.toPermit(),
            order.transferDetails(to),
            order.info.swapper,
            order.hash,
            RelayOrderLib.PERMIT2_ORDER_TYPE,
            order.sig
        );
    }

    /// @notice validate the relay order fields
    /// @dev Throws if the order is invalid
    function _validateOrder(RelayOrder memory order) internal pure {
        // assert that actions are valid and allowed, that calldata is well formed, etc.
    }
}
