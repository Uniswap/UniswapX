// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {OrderInfo} from "../../../src/v4/base/ReactorStructs.sol";
import {IReactor} from "../../../src/interfaces/IReactor.sol";
import {IPreExecutionHook, IPostExecutionHook} from "../../../src/v4/interfaces/IHook.sol";

library OrderInfoBuilder {
    function init(address reactor) internal view returns (OrderInfo memory) {
        return OrderInfo({
            reactor: IReactor(reactor),
            swapper: address(0),
            nonce: 0,
            deadline: block.timestamp + 100,
            preExecutionHook: IPreExecutionHook(address(0)),
            preExecutionHookData: bytes(""),
            postExecutionHook: IPostExecutionHook(address(0)),
            postExecutionHookData: bytes("")
        });
    }

    function withSwapper(OrderInfo memory info, address _swapper) internal pure returns (OrderInfo memory) {
        info.swapper = _swapper;
        return info;
    }

    function withNonce(OrderInfo memory info, uint256 _nonce) internal pure returns (OrderInfo memory) {
        info.nonce = _nonce;
        return info;
    }

    function withDeadline(OrderInfo memory info, uint256 _deadline) internal pure returns (OrderInfo memory) {
        info.deadline = _deadline;
        return info;
    }

    function withPreExecutionHook(OrderInfo memory info, IPreExecutionHook _preExecutionHook)
        internal
        pure
        returns (OrderInfo memory)
    {
        info.preExecutionHook = _preExecutionHook;
        return info;
    }

    function withPreExecutionHookData(OrderInfo memory info, bytes memory _preExecutionHookData)
        internal
        pure
        returns (OrderInfo memory)
    {
        info.preExecutionHookData = _preExecutionHookData;
        return info;
    }
}
