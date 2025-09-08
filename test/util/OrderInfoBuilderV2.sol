// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {OrderInfoV2} from "../../src/base/ReactorStructs.sol";
import {IReactor} from "../../src/interfaces/IReactor.sol";
import {IPreExecutionHook, IPostExecutionHook} from "../../src/interfaces/IHook.sol";

library OrderInfoBuilderV2 {
    function init(address reactor) internal view returns (OrderInfoV2 memory) {
        return OrderInfoV2({
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

    function withSwapper(OrderInfoV2 memory info, address _swapper) internal pure returns (OrderInfoV2 memory) {
        info.swapper = _swapper;
        return info;
    }

    function withNonce(OrderInfoV2 memory info, uint256 _nonce) internal pure returns (OrderInfoV2 memory) {
        info.nonce = _nonce;
        return info;
    }

    function withDeadline(OrderInfoV2 memory info, uint256 _deadline) internal pure returns (OrderInfoV2 memory) {
        info.deadline = _deadline;
        return info;
    }

    function withPreExecutionHook(OrderInfoV2 memory info, IPreExecutionHook _preExecutionHook)
        internal
        pure
        returns (OrderInfoV2 memory)
    {
        info.preExecutionHook = _preExecutionHook;
        return info;
    }

    function withPreExecutionHookData(OrderInfoV2 memory info, bytes memory _preExecutionHookData)
        internal
        pure
        returns (OrderInfoV2 memory)
    {
        info.preExecutionHookData = _preExecutionHookData;
        return info;
    }
}
