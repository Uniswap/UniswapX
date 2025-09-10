// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IReactor} from "../../src/interfaces/IReactor.sol";
import {IReactorCallback} from "./interfaces/IReactorCallback.sol";

import {SignedOrder, OutputToken} from "../../src/base/ReactorStructs.sol";
import {ResolvedOrder} from "./base/ReactorStructs.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {IAuctionResolver} from "./interfaces/IAuctionResolver.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {CurrencyLibrary} from "../../src/lib/CurrencyLibrary.sol";
import {ReactorEvents} from "../../src/base/ReactorEvents.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {ProtocolFees} from "./base/ProtocolFees.sol";

/// @notice Unified reactor that supports pre-and-post fill hooks and auction resolver plugins
/// @dev Does not inherit from BaseReactor
contract UnifiedReactor is IReactor, ReactorEvents, ProtocolFees, ReentrancyGuard {
    using CurrencyLibrary for address;

    /// @notice thrown when an auction resolver is not set
    error EmptyAuctionResolver();
    /// @notice thrown when an order's nonce has already been used
    error InvalidNonce();
    /// @notice thrown when the order targets a different reactor
    error InvalidReactor();
    /// @notice thrown when the order's deadline has passed
    error DeadlinePassed();
    /// @notice thrown when a pre-execution hook is not set
    error MissingPreExecutionHook();

    /// @notice Permit2 instance for signature verification and token transfers
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
    }

    /// @notice Prepare orders for execution (validation and pre-execution hooks)
    function _prepare(ResolvedOrder[] memory orders) internal {
        uint256 ordersLength = orders.length;
        unchecked {
            for (uint256 i = 0; i < ordersLength; i++) {
                ResolvedOrder memory order = orders[i];
                _injectFees(order);
                _validateOrder(order);
                _callPreExecutionHook(order);
                // Token transfer is now handled by the hook
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
                emit Fill(order.hash, msg.sender, order.info.swapper, order.info.nonce);
            }
        }
        _callPostExecutionHook(orders);
    }

    /// @notice Call post-execution hook if set
    function _callPostExecutionHook(ResolvedOrder[] memory orders) internal {
        uint256 ordersLength = orders.length;
        unchecked {
            for (uint256 i = 0; i < ordersLength; i++) {
                ResolvedOrder memory order = orders[i];
                if (address(order.info.postExecutionHook) != address(0)) {
                    order.info.postExecutionHook.postExecutionHook(msg.sender, order);
                }
            }
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
                if (output.token.isNative()) {
                    CurrencyLibrary.transferNative(output.recipient, output.amount);
                } else {
                    ERC20(output.token).transferFrom(msg.sender, output.recipient, output.amount);
                }
            }
        }
    }

    /// @notice Allow contract to receive ETH for native output orders
    receive() external payable {}
}
