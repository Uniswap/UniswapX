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
        address taker;
        address inputToken;
        uint256 inputAmount;
        (taker, inputToken, inputAmount) = abi.decode(
            fillData, (address, address, uint256)
        );
        // transfer output tokens from taker to this
        for (uint256 i = 0; i < outputs.length; i++) {
            Output memory output = outputs[i];
            ERC20(output.token).transferFrom(taker, address(this), output.amount);
        }
        // transfer input tokens from this to taker
        ERC20(inputToken).transfer(taker, inputAmount);
    }
}