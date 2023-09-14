// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {CurrencyLibrary} from "../../../src/lib/CurrencyLibrary.sol";
import {ResolvedOrder, OutputToken, SignedOrder} from "../../../src/base/ReactorStructs.sol";
import {IReactor} from "../../../src/interfaces/IReactor.sol";
import {IReactorCallback} from "../../../src/interfaces/IReactorCallback.sol";

contract MockFillContractWithOutputOverride is IReactorCallback {
    using CurrencyLibrary for address;

    uint256 outputAmount;

    IReactor immutable reactor;

    constructor(address _reactor) {
        reactor = IReactor(_reactor);
    }

    // override for sending less than reactor amount
    function setOutputAmount(uint256 amount) external {
        outputAmount = amount;
    }

    /// @notice assume that we already have all output tokens
    function execute(SignedOrder calldata order) external {
        reactor.executeWithCallback(order, hex"");
    }

    /// @notice assume that we already have all output tokens
    function executeBatch(SignedOrder[] calldata orders) external {
        reactor.executeBatchWithCallback(orders, hex"");
    }

    /// @notice assume that we already have all output tokens
    function reactorCallback(ResolvedOrder[] memory resolvedOrders, bytes memory) external {
        for (uint256 i = 0; i < resolvedOrders.length; i++) {
            for (uint256 j = 0; j < resolvedOrders[i].outputs.length; j++) {
                OutputToken memory output = resolvedOrders[i].outputs[j];
                uint256 amount = outputAmount == 0 ? output.amount : outputAmount;
                if (output.token.isNative()) {
                    CurrencyLibrary.transferNative(address(reactor), amount);
                } else {
                    ERC20(output.token).approve(address(reactor), type(uint256).max);
                }
            }
        }
    }
}
