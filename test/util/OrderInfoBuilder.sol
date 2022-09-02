// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Output, OrderInfo} from "../../src/lib/ReactorStructs.sol";

library OrderInfoBuilder {
    function init(address reactor) internal view returns (OrderInfo memory) {
        return OrderInfo({reactor: reactor, offerer: address(0), counter: 0, deadline: block.timestamp});
    }

    function withOfferer(OrderInfo memory info, address _offerer) internal pure returns (OrderInfo memory) {
        info.offerer = _offerer;
        return info;
    }

    function withCounter(OrderInfo memory info, uint256 _counter) internal pure returns (OrderInfo memory) {
        info.counter = _counter;
        return info;
    }

    function withDeadline(OrderInfo memory info, uint256 _deadline) internal pure returns (OrderInfo memory) {
        info.deadline = _deadline;
        return info;
    }
}
