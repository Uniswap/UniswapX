// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {Output} from "../interfaces/ReactorStructs.sol";
import {IReactorCallback} from "../interfaces/IReactorCallback.sol";

contract MockFillContract is IReactorCallback {
    /// @notice assume that we already have all output tokens
    function reactorCallback(Output[] memory outputs, bytes memory) external {
        for (uint256 i = 0; i < outputs.length; i++) {
            ERC20 token = ERC20(outputs[i].token);
            token.approve(msg.sender, outputs[i].amount);
        }
    }
}
