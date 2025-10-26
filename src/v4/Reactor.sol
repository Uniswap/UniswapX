// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IReactor} from "./interfaces/IReactor.sol";
import {IReactorCallback} from "./interfaces/IReactorCallback.sol";

import {SignedOrder, OutputToken} from "../../src/base/ReactorStructs.sol";
import {ResolvedOrder, GenericOrder, GENERIC_ORDER_TYPE_HASH} from "./base/ReactorStructs.sol";
import {IAuctionResolver} from "./interfaces/IAuctionResolver.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {CurrencyLibrary} from "../../src/lib/CurrencyLibrary.sol";
import {ReactorEvents} from "../../src/base/ReactorEvents.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {ProtocolFees} from "./base/ProtocolFees.sol";

/// @notice modular UniswapX Reactor that supports pre-and-post fill hooks and auction resolver plugins
contract Reactor is IReactor, ReactorEvents, ProtocolFees, ReentrancyGuard {
    using CurrencyLibrary for address;

    constructor(address _protocolFeeOwner) ProtocolFees(_protocolFeeOwner) {}

    /// @inheritdoc IReactor
    function execute(SignedOrder calldata order) external payable override nonReentrant {
        ResolvedOrder[] memory resolvedOrders = new ResolvedOrder[](1);
        resolvedOrders[0] = _resolve(order);
        _prepare(resolvedOrders);
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

    /// @notice Resolve a SignedOrder into a ResolvedOrder using the auction resolver
    function _resolve(SignedOrder calldata signedOrder) internal view returns (ResolvedOrder memory resolvedOrder) {
        (address auctionResolver, bytes memory orderData) = abi.decode(signedOrder.order, (address, bytes));

        if (auctionResolver == address(0)) {
            revert EmptyAuctionResolver();
        }

        IAuctionResolver resolver = IAuctionResolver(auctionResolver);
        resolvedOrder = resolver.resolve(SignedOrder({order: orderData, sig: signedOrder.sig}));

        if (address(resolvedOrder.info.auctionResolver) != auctionResolver) {
            revert ResolverMismatch();
        }

        // Compute GenericOrder witness hash to bind resolver address to order hash
        // This prevents malicious resolvers from manipulating order data
        bytes32 finalOrderHash = keccak256(abi.encode(GENERIC_ORDER_TYPE_HASH, auctionResolver, resolvedOrder.hash));
        resolvedOrder.hash = finalOrderHash;
    }

    /// @notice Prepare orders for execution by calling pre-execution hooks and injecting fees
    function _prepare(ResolvedOrder[] memory orders) internal {
        uint256 ordersLength = orders.length;
        unchecked {
            for (uint256 i = 0; i < ordersLength; i++) {
                ResolvedOrder memory order = orders[i];
                _validateOrder(order);
                _callPreExecutionHook(order);
                _injectFees(order);
                // Token transfer is handled by the hook
            }
        }
    }

    /// @notice Fill orders by transferring output tokens
    function _fill(ResolvedOrder[] memory orders) internal {
        uint256 ordersLength = orders.length;
        unchecked {
            for (uint256 i = 0; i < ordersLength; i++) {
                ResolvedOrder memory order = orders[i];
                _transferOutputTokens(order);
                _callPostExecutionHook(order);
                emit Fill(order.hash, msg.sender, order.info.swapper, order.info.nonce);
            }
        }
    }

    /// @notice Call post-execution hook if set
    function _callPostExecutionHook(ResolvedOrder memory order) internal {
        if (address(order.info.postExecutionHook) != address(0)) {
            order.info.postExecutionHook.postExecutionHook(msg.sender, order);
        }
    }

    /// @notice Validate basic order properties
    function _validateOrder(ResolvedOrder memory order) internal view {
        if (address(this) != address(order.info.reactor)) {
            revert InvalidReactor();
        }

        if (order.info.deadline < block.timestamp) {
            revert DeadlinePassed();
        }
    }

    /// @notice Call pre-execution hook (required for all orders)
    function _callPreExecutionHook(ResolvedOrder memory order) internal {
        if (address(order.info.preExecutionHook) == address(0)) {
            revert MissingPreExecutionHook();
        }
        order.info.preExecutionHook.preExecutionHook(msg.sender, order);
    }

    /// @notice Transfer output tokens to their recipients
    function _transferOutputTokens(ResolvedOrder memory order) internal {
        uint256 outputsLength = order.outputs.length;
        unchecked {
            for (uint256 i = 0; i < outputsLength; i++) {
                OutputToken memory output = order.outputs[i];
                output.token.transferFill(output.recipient, output.amount);
            }
        }
    }

    /// @notice Allow contract to receive ETH for native output orders
    receive() external payable {}
}
