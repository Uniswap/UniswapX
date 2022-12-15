pragma solidity ^0.8.16;

import {OrderInfo, ResolvedOrder} from "../../../src/base/ReactorStructs.sol";
import {OrderInfoLib} from "../../../src/lib/OrderInfoLib.sol";

contract MockOrderInfoLib {
    using OrderInfoLib for OrderInfo;

    function validate(OrderInfo memory order, address filler, ResolvedOrder memory resolvedOrder) external view {
        order.validate(filler, resolvedOrder);
    }
}
