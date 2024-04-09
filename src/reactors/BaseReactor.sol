// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {SafeTransferLib} from "solmate/src/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/security/ReentrancyGuard.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ReactorEvents} from "../base/ReactorEvents.sol";
import {ResolvedOrderLib} from "../lib/ResolvedOrderLib.sol";
import {CurrencyLibrary} from "../lib/CurrencyLibrary.sol";
import {IReactorCallback} from "../interfaces/IReactorCallback.sol";
import {IReactor} from "../interfaces/IReactor.sol";
import {ProtocolFees} from "../base/ProtocolFees.sol";
import {SignedOrder, ResolvedOrder, OutputToken} from "../base/ReactorStructs.sol";

/// @notice Generic reactor logic for settling off-chain signed orders
///     using arbitrary fill methods specified by a filler
abstract contract BaseReactor is IReactor, ReactorEvents, ProtocolFees, ReentrancyGuard {
    using SafeTransferLib for ERC20;
    using ResolvedOrderLib for ResolvedOrder;
    using CurrencyLibrary for address;

    /// @notice permit2 address used for token transfers and signature verification
    IPermit2 public immutable permit2;

    constructor(IPermit2 _permit2, address _protocolFeeOwner) ProtocolFees(_protocolFeeOwner) {
        permit2 = _permit2;
    }

    /// @inheritdoc IReactor
    function execute(SignedOrder calldata order) external payable override nonReentrant {
        ResolvedOrder[] memory resolvedOrders = new ResolvedOrder[](1);
        resolvedOrders[0] = _resolve(order);

        _prepare(resolvedOrders);
        _fill(resolvedOrders);
    }

    /// @inheritdoc IReactor
    function executeWithCallback(SignedOrder calldata order, bytes calldata callbackData)
        external
        payable
        override
        nonReentrant
    {
        ResolvedOrder[] memory resolvedOrders = new ResolvedOrder[](1);
        resolvedOrders[0] = _resolve(order);

        _prepare(resolvedOrders);
        IReactorCallback(msg.sender).reactorCallback(resolvedOrders, callbackData);
        _fill(resolvedOrders);
    }

    /// @inheritdoc IReactor
    function executeBatch(SignedOrder[] calldata orders) external payable override nonReentrant {
        uint256 ordersLength = orders.length;
        ResolvedOrder[] memory resolvedOrders = new ResolvedOrder[](ordersLength);

        unchecked {
            for (uint256 i = 0; i < ordersLength; i++) {
                resolvedOrders[i] = _resolve(orders[i]);
            }
        }

        _prepare(resolvedOrders);
        _fill(resolvedOrders);
    }

    /// @inheritdoc IReactor
    function executeBatchWithCallback(SignedOrder[] calldata orders, bytes calldata callbackData)
        external
        payable
        override
        nonReentrant
    {
        uint256 ordersLength = orders.length;
        ResolvedOrder[] memory resolvedOrders = new ResolvedOrder[](ordersLength);

        unchecked {
            for (uint256 i = 0; i < ordersLength; i++) {
                resolvedOrders[i] = _resolve(orders[i]);
            }
        }

        _prepare(resolvedOrders);
        IReactorCallback(msg.sender).reactorCallback(resolvedOrders, callbackData);
        _fill(resolvedOrders);
    }

    /// @notice validates, injects fees, and transfers input tokens in preparation for order fill
    /// @param orders The orders to prepare
    function _prepare(ResolvedOrder[] memory orders) internal {
        uint256 ordersLength = orders.length;
        unchecked {
            for (uint256 i = 0; i < ordersLength; i++) {
                ResolvedOrder memory order = orders[i];
                _injectFees(order);
                order.validate(msg.sender);
                _transferInputTokens(order, msg.sender);
            }
        }
    }

    /// @notice fills a list of orders, ensuring all outputs are satisfied
    /// @param orders The orders to fill
    function _fill(ResolvedOrder[] memory orders) internal {
        uint256 ordersLength = orders.length;
        // attempt to transfer all currencies to all recipients
        unchecked {
            // transfer output tokens to their respective recipients
            for (uint256 i = 0; i < ordersLength; i++) {
                ResolvedOrder memory resolvedOrder = orders[i];
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

    /// @notice Resolve order-type specific requirements into a generic order with the final inputs and outputs.
    /// @param order The encoded order to resolve
    /// @return resolvedOrder generic resolved order of inputs and outputs
    /// @dev should revert on any order-type-specific validation errors
    function _resolve(SignedOrder calldata order) internal view virtual returns (ResolvedOrder memory resolvedOrder);

    /// @notice Transfers tokens to the fillContract
    /// @param order The encoded order to transfer tokens for
    /// @param to The address to transfer tokens to
    function _transferInputTokens(ResolvedOrder memory order, address to) internal virtual;
}
