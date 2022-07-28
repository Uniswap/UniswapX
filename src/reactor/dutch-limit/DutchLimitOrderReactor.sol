// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {OrderFiller} from "../../lib/OrderFiller.sol";
import {OrderValidator} from "../../lib/OrderValidator.sol";
import {DutchLimitOrder, DutchLimitOrderExecution} from "./DutchLimitOrderStructs.sol";
import {ResolvedOrder, TokenAmount} from "../../interfaces/ReactorStructs.sol";

/// @notice Reactor for simple limit orders
contract DutchLimitOrderReactor is OrderValidator {
    using OrderFiller for ResolvedOrder;

    function execute(DutchLimitOrderExecution calldata execution) external {
        validateOrder(execution.order.info);
        ResolvedOrder memory order =
        ResolvedOrder(execution.order.input, execution.order.outputs);
        order.fill(
            execution.order.info.offerer,
            execution.sig,
            execution.fillContract,
            execution.fillData
        );
    }
}
