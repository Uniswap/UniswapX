// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {IReactorCallback} from "../interfaces/IReactorCallback.sol";
import {Output} from "../interfaces/ReactorStructs.sol";

contract DirectTakerExecutor is IReactorCallback {
    function reactorCallback(
        Output[] memory outputs,
        bytes memory fillData
    ) external {
        address taker = abi.decode(fillData, (address));
        // transfer output tokens to reactor
        for (uint256 i = 0; i < outputs.length; i++) {
            Output memory output = outputs[i];
            ERC20(output.token).transferFrom(taker, msg.sender, output.amount);
        }
    }
}