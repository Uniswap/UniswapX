// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {SettlementInfo} from "../../../src/xchain-gouda/base/SettlementStructs.sol";

library SettlementInfoBuilder {
    function init(address settler) internal view returns (SettlementInfo memory) {
        return SettlementInfo({
            settlerContract: settler,
            offerer: address(0),
            nonce: 0,
            initiateDeadline: block.timestamp + 100,
            settlementPeriod: 100,
            settlementOracle: address(0),
            validationContract: address(0),
            validationData: bytes("")
        });
    }

    function withOfferer(SettlementInfo memory info, address _offerer) internal pure returns (SettlementInfo memory) {
        info.offerer = _offerer;
        return info;
    }

    function withOracle(SettlementInfo memory info, address _settlementOracle)
        internal
        pure
        returns (SettlementInfo memory)
    {
        info.settlementOracle = _settlementOracle;
        return info;
    }

    function withNonce(SettlementInfo memory info, uint256 _nonce) internal pure returns (SettlementInfo memory) {
        info.nonce = _nonce;
        return info;
    }

    function withDeadline(SettlementInfo memory info, uint256 _deadline)
        internal
        pure
        returns (SettlementInfo memory)
    {
        info.initiateDeadline = _deadline;
        return info;
    }

    function withValidationContract(SettlementInfo memory info, address _validationContract)
        internal
        pure
        returns (SettlementInfo memory)
    {
        info.validationContract = _validationContract;
        return info;
    }

    function withValidationData(SettlementInfo memory info, bytes memory _validationData)
        internal
        pure
        returns (SettlementInfo memory)
    {
        info.validationData = _validationData;
        return info;
    }
}
