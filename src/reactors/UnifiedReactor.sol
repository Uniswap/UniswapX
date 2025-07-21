// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {BaseReactor} from "./BaseReactor.sol";
import {Permit2Lib} from "../lib/Permit2Lib.sol";
import {SignedOrder, ResolvedOrder, OutputToken} from "../base/ReactorStructs.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {IAuctionResolver} from "../interfaces/IAuctionResolver.sol";
import {IDCARegistry} from "../interfaces/IDCARegistry.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {CurrencyLibrary} from "../lib/CurrencyLibrary.sol";

/// @notice Unified reactor that supports both AllowanceTransfer and SignatureTransfer
/// with pluggable auction mechanisms
contract UnifiedReactor is BaseReactor {
    using Permit2Lib for ResolvedOrder;
    using CurrencyLibrary for address;

    /// @notice thrown when an auction resolver is not set
    error EmptyAuctionResolver();

    constructor(IPermit2 _permit2, address _protocolFeeOwner) BaseReactor(_permit2, _protocolFeeOwner) {}

    /// @inheritdoc BaseReactor
    function _resolve(SignedOrder calldata signedOrder)
        internal
        view
        override
        returns (ResolvedOrder memory resolvedOrder)
    {
        (address auctionResolver, bytes memory orderData) = abi.decode(signedOrder.order, (address, bytes));

        if (auctionResolver == address(0)) {
            revert EmptyAuctionResolver();
        }

        SignedOrder memory resolverOrder = SignedOrder({
            order: orderData,
            sig: signedOrder.sig
        });

        IAuctionResolver resolver = IAuctionResolver(auctionResolver);
        resolvedOrder = resolver.resolve(resolverOrder);
    }

    /// @inheritdoc BaseReactor
    function _transferInputTokens(ResolvedOrder memory order, address to) internal override {
        if (order.info.additionalValidationData.length > 0 && order.info.additionalValidationData[0] == 0x01) {
            // Use AllowanceTransfer for DCA orders
            IAllowanceTransfer.AllowanceTransferDetails memory details = IAllowanceTransfer.AllowanceTransferDetails({
                from: order.info.swapper,
                to: to,
                amount: uint160(order.input.amount),
                token: address(order.input.token)
            });

            IAllowanceTransfer(address(permit2)).transferFrom(details.from, details.to, details.amount, details.token);
        } else {
            // Use SignatureTransfer - get the order type from the resolver
            string memory orderType = IAuctionResolver(order.auctionResolver).getPermit2OrderType();
            
            permit2.permitWitnessTransferFrom(
                order.toPermit(),
                order.transferDetails(to),
                order.info.swapper,
                order.hash,
                orderType,
                order.sig
            );
        }
    }
}
