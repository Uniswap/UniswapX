// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {SignedOrder} from "../../../../src/base/ReactorStructs.sol";
import {IReactor} from "../../../../src/interfaces/IReactor.sol";
import {IReactorCallback} from "../../../../src/interfaces/IReactorCallback.sol";

contract MockDirectFiller {
    function approve(address token, address to, uint256 amount) external {
        ERC20(token).approve(to, amount);
    }

    function execute(IReactor reactor, SignedOrder memory order, IReactorCallback fillContract, bytes calldata fillData)
        external
    {
        reactor.execute(order, fillContract, fillData);
    }
}
