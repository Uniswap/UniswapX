// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {OutputToken, SettlementKey} from "../../../../src/xchain-gouda/base/SettlementStructs.sol";
import {SignedOrder} from "../../../../src/base/ReactorStructs.sol";
import {ISettlementOracle} from "../../../../src/xchain-gouda/interfaces/ISettlementOracle.sol";
import {IOrderSettler} from "../../../../src/xchain-gouda/interfaces/IOrderSettler.sol";

/// @notice Interface for cross chain listener oracles for cross-chain gouda
contract MockSettlementOracle is ISettlementOracle {
    function finalizeSettlement(bytes32 orderHash, SettlementKey memory key, address settler, uint256 fillTimestamp)
        external
    {
        IOrderSettler(settler).finalize(orderHash, key, fillTimestamp);
    }
}
