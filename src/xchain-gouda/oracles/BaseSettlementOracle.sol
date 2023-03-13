// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {ISettlementOracle} from "../interfaces/ISettlementOracle.sol";
import {IOrderSettler} from "../interfaces/IOrderSettler.sol";
import {OutputToken, SettlementKey} from "../base/SettlementStructs.sol";

/// @notice Generic cross-chain filler logic for filling an order on the target chain
abstract contract BaseSettlementOracle is ISettlementOracle {
    /// @inheritdoc ISettlementOracle
    function finalizeSettlement(bytes32 orderId, SettlementKey memory key, address settler, uint256 fillTimestamp)
        external
    {
        authenticateMessageOrigin();
        IOrderSettler(settler).finalize(orderId, key, fillTimestamp);
    }

    /// @notice verifies that the cross chain message came from a legitimate source
    /// @dev this function must revert if msg.sender is not valid bridge contract or if the message was initiated
    /// from a contract on the target chain that is not a valid SettlementFiller
    function authenticateMessageOrigin() internal virtual;
}
