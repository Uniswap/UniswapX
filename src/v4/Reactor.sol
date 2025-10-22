// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IReactor} from "./interfaces/IReactor.sol";
import {IReactorCallback} from "./interfaces/IReactorCallback.sol";

import {SignedOrder, OutputToken} from "../../src/base/ReactorStructs.sol";
import {ResolvedOrder, GenericOrder, GENERIC_ORDER_TYPE_HASH} from "./base/ReactorStructs.sol";
import {IAuctionResolver} from "./interfaces/IAuctionResolver.sol";
import {CurrencyLibrary} from "../../src/lib/CurrencyLibrary.sol";
import {ReactorEvents} from "../../src/base/ReactorEvents.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {SignatureVerification} from "permit2/src/libraries/SignatureVerification.sol";
import {ProtocolFees} from "./base/ProtocolFees.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";

/// @notice modular UniswapX Reactor that supports pre-and-post fill hooks and auction resolver plugins
contract Reactor is IReactor, ReactorEvents, ProtocolFees, ReentrancyGuard {
    using CurrencyLibrary for address;
    using SignatureVerification for bytes;

    /// @notice Permit2 address for EIP-712 domain separator
    IPermit2 public immutable permit2;

    bytes32 private constant _TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");

    string private constant _PERMIT_TRANSFER_FROM_WITNESS_TYPEHASH_STUB =
        "PermitWitnessTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline,";

    constructor(address _protocolFeeOwner, IPermit2 _permit2) ProtocolFees(_protocolFeeOwner) {
        permit2 = _permit2;
    }

    /// @inheritdoc IReactor
    function execute(SignedOrder calldata order) external payable override nonReentrant {
        ResolvedOrder[] memory resolvedOrders = new ResolvedOrder[](1);
        ResolvedOrder memory resolvedOrder = _resolve(order);
        resolvedOrders[0] = resolvedOrder;

        // Build full EIP-712 hash for signature verification
        bytes32 fullHash = _buildPermitHash(resolvedOrder);
        order.sig.verify(fullHash, resolvedOrder.info.swapper);

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
                bytes32 fullHash = _buildPermitHash(resolvedOrders[i]);
                orders[i].sig.verify(fullHash, resolvedOrders[i].info.swapper);
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
        ResolvedOrder memory resolvedOrder = _resolve(order);
        resolvedOrders[0] = resolvedOrder;
        bytes32 fullHash = _buildPermitHash(resolvedOrder);
        order.sig.verify(fullHash, resolvedOrder.info.swapper);

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
                bytes32 fullHash = _buildPermitHash(resolvedOrders[i]);
                orders[i].sig.verify(fullHash, resolvedOrders[i].info.swapper);
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

        // Resolver provides the witness hash that binds resolver to order
        // No need to wrap it again - the witness already includes the resolver address
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

    /// @notice Build the full EIP-712 hash for signature verification
    /// @param order The resolved order
    /// @return The full EIP-712 hash that was signed by the swapper
    function _buildPermitHash(ResolvedOrder memory order) internal view returns (bytes32) {
        // Build the full PermitWitnessTransferFrom type hash from the witness type string
        // based on `PermitHash.hashWithWitness` logic
        bytes32 typeHash =
            keccak256(abi.encodePacked(_PERMIT_TRANSFER_FROM_WITNESS_TYPEHASH_STUB, order.witnessTypeString));

        // based `PermitHash._hashTokenPermissions` logic
        bytes32 tokenPermissionsHash =
            keccak256(abi.encode(_TOKEN_PERMISSIONS_TYPEHASH, address(order.input.token), order.input.maxAmount));

        bytes32 structHash = keccak256(
            abi.encode(
                typeHash,
                tokenPermissionsHash,
                address(order.info.preExecutionHook), // spender
                order.info.nonce,
                order.info.deadline,
                order.hash
            )
        );

        return keccak256(abi.encodePacked("\x19\x01", permit2.DOMAIN_SEPARATOR(), structHash));
    }

    /// @notice Allow contract to receive ETH for native output orders
    receive() external payable {}
}
