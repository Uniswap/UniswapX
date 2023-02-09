// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {ISettlementOracle} from "../interfaces/ISettlementOracle.sol";
import {IOrderSettler} from "../interfaces/IOrderSettler.sol";
import {OutputToken, ActiveSettlement} from "../base/SettlementStructs.sol";

contract L2SettlementOracle is ISettlementOracle {
    error SenderIsNotValidBridge();
    error FillerIsNotValid();
    error InvalidRecipient(bytes32 orderId, uint16 outputIndex);
    error InvalidToken(bytes32 orderId, uint16 outputIndex);
    error InvalidAmount(bytes32 orderId, uint16 outputIndex);
    error InvalidChain(bytes32 orderId, uint16 outputIndex);

    address public immutable L2_MESSENGER;
    address public immutable ORDER_SETTLER;

    mapping(bytes32 => bool) public settled;

    constructor(address l2CrossDomainMessenger, address orderSettler) {
        L2_MESSENGER = l2CrossDomainMessenger;
        ORDER_SETTLER = orderSettler;
    }

    function logSettlementFillInfo(bytes32 orderId, address targetChainFiller, OutputToken[] calldata outputs) public {
        if (msg.sender != L2_MESSENGER) revert SenderIsNotValidBridge();

        ActiveSettlement memory settlement = IOrderSettler(ORDER_SETTLER).settlements(orderId);

        if (settlement.targetChainFiller != targetChainFiller) revert FillerIsNotValid();

        for (uint16 i; i < outputs.length; i++) {
            OutputToken memory expectedOutput = settlement.outputs[i];
            OutputToken memory receivedOutput = outputs[i];
            if (expectedOutput.recipient != receivedOutput.recipient) revert InvalidRecipient(orderId, i);
            if (expectedOutput.token != receivedOutput.token) revert InvalidToken(orderId, i);
            if (expectedOutput.amount < receivedOutput.amount) revert InvalidAmount(orderId, i);
            if (expectedOutput.chainId != receivedOutput.chainId) revert InvalidChain(orderId, i);
        }

        settled[orderId] = true;
    }
}
