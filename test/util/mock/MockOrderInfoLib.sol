pragma solidity ^0.8.16;

import {OrderInfo} from "../../../src/base/ReactorStructs.sol";
import {OrderInfoLib} from "../../../src/lib/OrderInfoLib.sol";
import "forge-std/console.sol";

contract MockOrderInfoLib {
    using OrderInfoLib for OrderInfo;

    function validate(OrderInfo memory order) external view {
        order.validate();
    }
}
