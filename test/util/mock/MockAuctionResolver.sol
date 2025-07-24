// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IAuctionResolver} from "../../../src/interfaces/IAuctionResolver.sol";
import {SignedOrder, ResolvedOrderV2, InputToken, OutputToken} from "../../../src/base/ReactorStructs.sol";
import {PriorityOrderV2, PriorityOrderLibV2} from "../../../src/lib/PriorityOrderLib.sol";

/// @notice Mock auction resolver for testing that returns orders as-is
contract MockAuctionResolver is IAuctionResolver {
    using PriorityOrderLibV2 for PriorityOrderV2;
    /// @inheritdoc IAuctionResolver

    function auctionType() external pure override returns (string memory) {
        return "Mock";
    }

    /// @inheritdoc IAuctionResolver
    function resolve(SignedOrder calldata signedOrder)
        external
        view
        override
        returns (ResolvedOrderV2 memory resolvedOrder)
    {
        PriorityOrderV2 memory order = abi.decode(signedOrder.order, (PriorityOrderV2));

        // Convert PriorityInput to InputToken
        InputToken memory input =
            InputToken({token: order.input.token, amount: order.input.amount, maxAmount: order.input.amount});

        // Convert PriorityOutput[] to OutputToken[]
        OutputToken[] memory outputs = new OutputToken[](order.outputs.length);
        for (uint256 i = 0; i < order.outputs.length; i++) {
            outputs[i] = OutputToken({
                token: order.outputs[i].token,
                amount: order.outputs[i].amount,
                recipient: order.outputs[i].recipient
            });
        }

        resolvedOrder = ResolvedOrderV2({
            info: order.info,
            input: input,
            outputs: outputs,
            sig: signedOrder.sig,
            hash: order.hash(),
            auctionResolver: address(this)
        });
    }

    /// @inheritdoc IAuctionResolver
    function getPermit2OrderType() external pure override returns (string memory) {
        return PriorityOrderLibV2.PERMIT2_ORDER_TYPE;
    }
}
