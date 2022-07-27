// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {IReactorCallback} from "../interfaces/IReactorCallback.sol";
import {
    TokenAmount,
    Output,
    ResolvedOrder,
    Signature
} from "../interfaces/ReactorStructs.sol";

library OrderFiller {
    /// @notice fill an order
    function fill(
        ResolvedOrder memory order,
        address offerer,
        Signature memory,
        address fillContract,
        bytes memory fillData
    )
        internal
    {
        // TODO: use permit post instead to send input tokens to fill contract
        // transfer input tokens to the fill contract
        ERC20(order.input.token).transferFrom(
            offerer, fillContract, order.input.amount
        );

        IReactorCallback(fillContract).reactorCallback(order.outputs, fillData);

        // transfer output tokens to their respective recipients
        for (uint256 i = 0; i < order.outputs.length; i++) {
            Output memory output = order.outputs[i];
            ERC20(output.token).transferFrom(
                fillContract, output.recipient, output.amount
            );
        }
    }
}
