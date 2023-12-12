// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {CurrencyLibrary} from "../../../src/lib/CurrencyLibrary.sol";
import {ResolvedOrder, OutputToken, SignedOrder} from "../../../src/base/ReactorStructs.sol";
import {BaseReactor} from "../../../src/reactors/BaseReactor.sol";
import {IReactor} from "../../../src/interfaces/IReactor.sol";
import {IReactorCallback} from "../../../src/interfaces/IReactorCallback.sol";

contract MockFillContractDoubleExecution is IReactorCallback {
    using CurrencyLibrary for address;

    IReactor immutable reactor1;
    IReactor immutable reactor2;

    constructor(address _reactor1, address _reactor2) {
        reactor1 = IReactor(_reactor1);
        reactor2 = IReactor(_reactor2);
    }

    /// @notice assume that we already have all output tokens
    function execute(SignedOrder calldata order, SignedOrder calldata other) external {
        reactor1.executeWithCallback(order, abi.encode(other));
    }

    /// @notice assume that we already have all output tokens
    function reactorCallback(ResolvedOrder[] memory resolvedOrders, bytes memory otherSignedOrder) external {
        for (uint256 i = 0; i < resolvedOrders.length; i++) {
            for (uint256 j = 0; j < resolvedOrders[i].outputs.length; j++) {
                OutputToken memory output = resolvedOrders[i].outputs[j];
                if (output.token.isNative()) {
                    CurrencyLibrary.transferNative(msg.sender, output.amount);
                } else {
                    ERC20(output.token).approve(msg.sender, type(uint256).max);
                }
            }
        }

        if (msg.sender == address(reactor1)) {
            reactor2.executeWithCallback(abi.decode(otherSignedOrder, (SignedOrder)), hex"");
        }
    }
}
