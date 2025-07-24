// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IReactor} from "../interfaces/IReactor.sol";
import {IReactorCallbackV2} from "../interfaces/IReactorCallbackV2.sol";

import {Permit2LibV2} from "../lib/Permit2LibV2.sol";
import {SignedOrder, ResolvedOrderV2, OutputToken} from "../base/ReactorStructs.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {IAuctionResolver} from "../interfaces/IAuctionResolver.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {CurrencyLibrary} from "../lib/CurrencyLibrary.sol";
import {ReactorEvents} from "../base/ReactorEvents.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

/// @notice Unified reactor that supports SignatureTransfer with pluggable auction mechanisms
/// @dev Does not inherit from BaseReactor - uses IPreExecutionHook directly
contract UnifiedReactor is IReactor, ReactorEvents, ReentrancyGuard {
    using Permit2LibV2 for ResolvedOrderV2;
    using CurrencyLibrary for address;

    /// @notice thrown when an auction resolver is not set
    error EmptyAuctionResolver();
    /// @notice thrown when an order's nonce has already been used
    error InvalidNonce();
    /// @notice thrown when the order targets a different reactor
    error InvalidReactor();
    /// @notice thrown when the order's deadline has passed
    error DeadlinePassed();

    /// @notice Permit2 instance for signature verification and token transfers
    IPermit2 public immutable permit2;

    /// @notice Protocol fee owner
    address public immutable protocolFeeOwner;

    constructor(IPermit2 _permit2, address _protocolFeeOwner) {
        permit2 = _permit2;
        protocolFeeOwner = _protocolFeeOwner;
    }

    /// @inheritdoc IReactor
    function execute(SignedOrder calldata order) external payable override nonReentrant {
        ResolvedOrderV2 memory resolvedOrder = _resolve(order);
        _executeOrder(resolvedOrder);
    }

    /// @inheritdoc IReactor
    function executeBatch(SignedOrder[] calldata orders) external payable override nonReentrant {
        uint256 ordersLength = orders.length;
        ResolvedOrderV2[] memory resolvedOrders = new ResolvedOrderV2[](ordersLength);

        unchecked {
            for (uint256 i = 0; i < ordersLength; i++) {
                resolvedOrders[i] = _resolve(orders[i]);
            }
        }

        _executeOrders(resolvedOrders);
    }

    /// @inheritdoc IReactor
    function executeWithCallback(SignedOrder calldata order, bytes calldata callbackData)
        external
        payable
        override
        nonReentrant
    {
        ResolvedOrderV2 memory resolvedOrder = _resolve(order);
        _validateOrder(resolvedOrder);
        _callPreExecutionHook(resolvedOrder);
        _transferInputTokens(resolvedOrder, msg.sender);

        ResolvedOrderV2[] memory resolvedOrders = new ResolvedOrderV2[](1);
        resolvedOrders[0] = resolvedOrder;
        IReactorCallbackV2(msg.sender).reactorCallback(resolvedOrders, callbackData);

        _transferOutputTokens(resolvedOrder);
        emit Fill(resolvedOrder.hash, msg.sender, resolvedOrder.info.swapper, resolvedOrder.info.nonce);
    }

    /// @inheritdoc IReactor
    function executeBatchWithCallback(SignedOrder[] calldata orders, bytes calldata callbackData)
        external
        payable
        override
        nonReentrant
    {
        uint256 ordersLength = orders.length;
        ResolvedOrderV2[] memory resolvedOrders = new ResolvedOrderV2[](ordersLength);

        unchecked {
            for (uint256 i = 0; i < ordersLength; i++) {
                resolvedOrders[i] = _resolve(orders[i]);
            }
        }

        _prepare(resolvedOrders);
        IReactorCallbackV2(msg.sender).reactorCallback(resolvedOrders, callbackData);
        _fill(resolvedOrders);
    }

    /// @notice Resolve a SignedOrder into a ResolvedOrderV2 using the auction resolver
    function _resolve(SignedOrder calldata signedOrder) internal view returns (ResolvedOrderV2 memory resolvedOrder) {
        (address auctionResolver, bytes memory orderData) = abi.decode(signedOrder.order, (address, bytes));

        if (auctionResolver == address(0)) {
            revert EmptyAuctionResolver();
        }

        SignedOrder memory resolverOrder = SignedOrder({order: orderData, sig: signedOrder.sig});

        IAuctionResolver resolver = IAuctionResolver(auctionResolver);
        resolvedOrder = resolver.resolve(resolverOrder);
    }

    /// @notice Execute a single resolved order
    function _executeOrder(ResolvedOrderV2 memory order) internal {
        _validateOrder(order);
        _callPreExecutionHook(order);
        _transferInputTokens(order, msg.sender);
        _transferOutputTokens(order);

        emit Fill(order.hash, msg.sender, order.info.swapper, order.info.nonce);
    }

    /// @notice Execute multiple resolved orders
    function _executeOrders(ResolvedOrderV2[] memory orders) internal {
        _prepare(orders);
        _fill(orders);
    }

    /// @notice Prepare orders for execution (validation and pre-execution hooks)
    function _prepare(ResolvedOrderV2[] memory orders) internal {
        uint256 ordersLength = orders.length;
        unchecked {
            for (uint256 i = 0; i < ordersLength; i++) {
                ResolvedOrderV2 memory order = orders[i];
                _validateOrder(order);
                _callPreExecutionHook(order);
                _transferInputTokens(order, msg.sender);
            }
        }
    }

    /// @notice Fill orders by transferring output tokens
    function _fill(ResolvedOrderV2[] memory orders) internal {
        uint256 ordersLength = orders.length;
        unchecked {
            for (uint256 i = 0; i < ordersLength; i++) {
                ResolvedOrderV2 memory order = orders[i];
                _transferOutputTokens(order);
                emit Fill(order.hash, msg.sender, order.info.swapper, order.info.nonce);
            }
        }
    }

    /// @notice Validate basic order properties
    function _validateOrder(ResolvedOrderV2 memory order) internal view {
        if (address(this) != address(order.info.reactor)) {
            revert InvalidReactor();
        }

        if (order.info.deadline < block.timestamp) {
            revert DeadlinePassed();
        }
    }

    /// @notice Call pre-execution hook if set
    function _callPreExecutionHook(ResolvedOrderV2 memory order) internal {
        if (address(order.info.preExecutionHook) != address(0)) {
            order.info.preExecutionHook.preExecutionHook(msg.sender, order);
        }
    }

    /// @notice Transfer input tokens from swapper to filler using permitWitnessTransferFrom
    function _transferInputTokens(ResolvedOrderV2 memory order, address to) internal {
        // Always use SignatureTransfer - get the order type from the resolver
        string memory orderType = IAuctionResolver(order.auctionResolver).getPermit2OrderType();

        permit2.permitWitnessTransferFrom(
            order.toPermit(), order.transferDetails(to), order.info.swapper, order.hash, orderType, order.sig
        );
    }

    /// @notice Transfer output tokens to their recipients
    function _transferOutputTokens(ResolvedOrderV2 memory order) internal {
        uint256 outputsLength = order.outputs.length;
        unchecked {
            for (uint256 i = 0; i < outputsLength; i++) {
                OutputToken memory output = order.outputs[i];
                if (output.token.isNative()) {
                    CurrencyLibrary.transferNative(output.recipient, output.amount);
                } else {
                    ERC20(output.token).transferFrom(msg.sender, output.recipient, output.amount);
                }
            }
        }
    }
}
