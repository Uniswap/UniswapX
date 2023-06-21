// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {ResolvedOrder, OutputToken} from "../base/ReactorStructs.sol";

/// @title ExclusiveOverride
/// @dev This library handles order exclusivity
///  giving the configured filler exclusive rights to fill the order before exclusivityEndTime
///  or enforcing an override price improvement by non-exclusive fillers
library ExclusivityOverrideLib {
    using FixedPointMathLib for uint256;

    /// @notice thrown when an order has strict exclusivity and the filler does not have it
    error NoExclusiveOverride();

    uint256 private constant STRICT_EXCLUSIVITY = 0;
    uint256 private constant BPS = 10_000;

    /// @notice Applies exclusivity override to the resolved order if necessary
    /// @param order The order to apply exclusivity override to
    /// @param exclusive The exclusive address
    /// @param exclusivityEndTime The exclusivity end time
    /// @param exclusivityOverrideBps The exclusivity override BPS
    function handleOverride(
        ResolvedOrder memory order,
        address exclusive,
        uint256 exclusivityEndTime,
        uint256 exclusivityOverrideBps
    ) internal view {
        // if the filler has fill right, we proceed with the order as-is
        if (checkExclusivity(exclusive, exclusivityEndTime)) {
            return;
        }

        // if override is 0, then assume strict exclusivity so the order cannot be filled
        if (exclusivityOverrideBps == STRICT_EXCLUSIVITY) {
            revert NoExclusiveOverride();
        }

        // scale outputs by override amount
        OutputToken[] memory outputs = order.outputs;
        for (uint256 i = 0; i < outputs.length;) {
            OutputToken memory output = outputs[i];
            output.amount = output.amount.mulDivDown(BPS + exclusivityOverrideBps, BPS);

            unchecked {
                i++;
            }
        }
    }

    /// @notice checks if the order currently passes the exclusivity check
    /// @dev if the order has no exclusivity, always returns true
    /// @dev if the order has exclusivity and the current filler is the exclusive address, returns true
    /// @dev if the order has exclusivity and the current filler is not the exclusive address, returns false
    function checkExclusivity(address exclusive, uint256 exclusivityEndTime) internal view returns (bool pass) {
        return exclusive == address(0) || block.timestamp > exclusivityEndTime || exclusive == msg.sender;
    }
}
