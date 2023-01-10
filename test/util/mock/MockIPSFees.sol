// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {ResolvedOrder} from "../../../src/base/ReactorStructs.sol";
import {IPSFees} from "../../../src/base/IPSFees.sol";

contract MockIPSFees is IPSFees {
    constructor(uint256 _protocolFeeBps, address _protocolFeeRecipient)
        IPSFees(_protocolFeeBps, _protocolFeeRecipient)
    {}

    function takeFees(ResolvedOrder memory order) external returns (ResolvedOrder memory) {
        _takeFees(order);
        return order;
    }
}
