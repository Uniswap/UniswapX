// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {OrderInfo} from "../../src/base/ReactorStructs.sol";
import {IReactor} from "../../src/interfaces/IReactor.sol";
import {IValidationCallback} from "../../src/interfaces/IValidationCallback.sol";

library OrderInfoBuilder {
    function init(address reactor) internal view returns (OrderInfo memory) {
        return OrderInfo({
            reactor: IReactor(reactor),
            swapper: address(0),
            nonce: 0,
            deadline: block.timestamp + 100,
            validationContract: IValidationCallback(address(0)),
            validationData: bytes("")
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

    function withValidationContract(OrderInfo memory info, IValidationCallback _validationContract)
        internal
        pure
        returns (OrderInfo memory)
    {
        info.validationContract = _validationContract;
        return info;
    }

    function withValidationData(OrderInfo memory info, bytes memory _validationData)
        internal
        pure
        returns (OrderInfo memory)
    {
        info.validationData = _validationData;
        return info;
    }
}
