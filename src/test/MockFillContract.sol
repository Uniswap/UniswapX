// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ResolvedOrder} from "../interfaces/ReactorStructs.sol";
import {IReactorCallback} from "../interfaces/IReactorCallback.sol";

contract MockFillContract is IReactorCallback {
    /// @notice assume that we already have all output tokens
    function reactorCallback(ResolvedOrder[] memory resolvedOrders, bytes memory) external {
        for (uint256 i = 0; i < resolvedOrders[0].outputs.length; i++) {
            ERC20 token = ERC20(resolvedOrders[0].outputs[i].token);
            token.approve(msg.sender, resolvedOrders[0].outputs[i].amount);
        }
    }
}
