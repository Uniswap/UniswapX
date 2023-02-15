// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ResolvedOrder, ETH_ADDRESS} from "../../../src/base/ReactorStructs.sol";
import {IReactorCallback} from "../../../src/interfaces/IReactorCallback.sol";

contract MockFillContract is IReactorCallback {
    /// @notice assume that we already have all output tokens
    function reactorCallback(ResolvedOrder[] memory resolvedOrders, address, bytes memory) external {
        uint256 ethToSendToReactor;
        for (uint256 i = 0; i < resolvedOrders.length; i++) {
            for (uint256 j = 0; j < resolvedOrders[i].outputs.length; j++) {
                if (resolvedOrders[i].outputs[j].token == ETH_ADDRESS) {
                    ethToSendToReactor += resolvedOrders[i].outputs[j].amount;
                } else {
                    ERC20 token = ERC20(resolvedOrders[i].outputs[j].token);
                    token.approve(msg.sender, type(uint256).max);
                }
            }
        }
        (bool sent,) = msg.sender.call{value: ethToSendToReactor}("");
        require(sent, "MockFillContract has insufficient ETH");
    }
}
