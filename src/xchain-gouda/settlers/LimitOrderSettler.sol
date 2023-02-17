// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {console} from "forge-std/console.sol";
import {BaseOrderSettler} from "./BaseOrderSettler.sol";
import {Permit2Lib} from "../lib/Permit2Lib.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {CrossChainLimitOrderLib, CrossChainLimitOrder} from "../lib/CrossChainLimitOrderLib.sol";
import {SignedOrder} from "../../base/ReactorStructs.sol";
import {ResolvedOrder, SettlementInfo, ActiveSettlement, InputToken, OutputToken} from "../base/SettlementStructs.sol";

/// @notice Reactor for simple limit orders
contract LimitOrderSettler is BaseOrderSettler {
    using Permit2Lib for ResolvedOrder;
    using CrossChainLimitOrderLib for CrossChainLimitOrder;

    constructor(address _permit2) BaseOrderSettler(_permit2) {}

    /// @inheritdoc BaseOrderSettler
    function resolve(SignedOrder calldata signedOrder)
        internal
        view
        override
        returns (ResolvedOrder memory resolvedOrder)
    {
        CrossChainLimitOrder memory limitOrder = abi.decode(signedOrder.order, (CrossChainLimitOrder));

        resolvedOrder = ResolvedOrder({
            info: limitOrder.info,
            input: limitOrder.input,
            fillerCollateral: limitOrder.fillerCollateral,
            challengerCollateral: limitOrder.challengerCollateral,
            outputs: limitOrder.outputs,
            sig: signedOrder.sig,
            hash: limitOrder.hash()
        });
    }

    /// @inheritdoc BaseOrderSettler
    function collectEscrowTokens(ResolvedOrder memory order) internal override {
        permit2.permitWitnessTransferFrom(
            order.toPermit(),
            order.transferDetails(),
            order.info.offerer,
            order.hash,
            CrossChainLimitOrderLib.PERMIT2_ORDER_TYPE,
            order.sig
        );

        IAllowanceTransfer(address(permit2)).transferFrom(
            msg.sender, address(this), uint160(order.fillerCollateral.amount), order.fillerCollateral.token
        );
    }

    /// @inheritdoc BaseOrderSettler
    function collectChallengeBond(ActiveSettlement memory settlement) internal override {
        IAllowanceTransfer(address(permit2)).transferFrom(
            msg.sender,
            address(this),
            uint160(settlement.challengerCollateral.amount),
            settlement.challengerCollateral.token
        );
    }
}
