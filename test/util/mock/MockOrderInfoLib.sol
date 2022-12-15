pragma solidity ^0.8.16;

import {OrderInfo, ResolvedOrder} from "../../../src/base/ReactorStructs.sol";
import {OrderInfoLib} from "../../../src/lib/OrderInfoLib.sol";

contract MockOrderInfoLib {
    using OrderInfoLib for ResolvedOrder;

    function validate(ResolvedOrder memory resolvedOrder, address filler) external view {
        resolvedOrder.validate(filler);
    }
}
