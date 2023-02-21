// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {IReactorCallback} from "../interfaces/IReactorCallback.sol";
import {SafeCast} from "openzeppelin-contracts/utils/math/SafeCast.sol";
import {OrderInfo, ResolvedOrder, OutputToken} from "../base/ReactorStructs.sol";
import {IValidationCallback} from "../interfaces/IValidationCallback.sol";

abstract contract OrderExecution {
    address internal constant DIRECT_TAKER_FILL_STRATEGY = address(1);
    address public immutable permit2;

    constructor(address _permit2) {
        permit2 = _permit2;
    }

    /// @notice fills the given orders using the given fill strategy
    function executeFillStrategy(ResolvedOrder[] memory orders, address fillContract, bytes calldata fillData)
        internal
    {
        if (fillContract == DIRECT_TAKER_FILL_STRATEGY) {
            for (uint256 i = 0; i < orders.length; i++) {
                ResolvedOrder memory order = orders[i];
                for (uint256 j = 0; j < order.outputs.length; j++) {
                    OutputToken memory output = order.outputs[j];
                    IAllowanceTransfer(permit2).transferFrom(
                        msg.sender, output.recipient, SafeCast.toUint160(output.amount), output.token
                    );
                }
            }
        } else {
            IReactorCallback(fillContract).reactorCallback(orders, msg.sender, fillData);
        }
    }
}
