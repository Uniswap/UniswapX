// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {FixedPointMathLib} from "solmate/src/utils/FixedPointMathLib.sol";
import {ResolvedOrder} from "../base/ReactorStructs.sol";
import {OutputToken} from "../../base/ReactorStructs.sol";

/// @title ExclusiveOverride
/// @dev This library handles order exclusivity for V4 orders
///  giving the configured filler exclusive rights to fill the order before exclusivityEnd
///  or enforcing an override price improvement by non-exclusive fillers
library ExclusivityLib {
    using FixedPointMathLib for uint256;

    /// @notice thrown when an order has strict exclusivity and the filler does not have it
    error NoExclusiveOverride();

    uint256 private constant STRICT_EXCLUSIVITY = 0;
    uint256 private constant BPS = 10_000;

    /// @notice Applies exclusivity override to the resolved order if necessary
    /// @param order The order to apply exclusivity override to
    /// @param exclusive The exclusive address
    /// @param exclusivityEnd The exclusivity end timestamp
    /// @param exclusivityOverrideBps The exclusivity override BPS
    function handleExclusiveOverrideTimestamp(
        ResolvedOrder memory order,
        address exclusive,
        uint256 exclusivityEnd,
        uint256 exclusivityOverrideBps
    ) internal view {
        _handleExclusiveOverride(order, exclusive, exclusivityEnd, exclusivityOverrideBps, block.timestamp);
    }

    /// @notice Applies exclusivity override to the resolved order if necessary
    /// @param order The order to apply exclusivity override to
    /// @param exclusive The exclusive address
    /// @param exclusivityEnd The exclusivity end block number
    /// @param exclusivityOverrideBps The exclusivity override BPS
    function handleExclusiveOverrideBlock(
        ResolvedOrder memory order,
        address exclusive,
        uint256 exclusivityEnd,
        uint256 exclusivityOverrideBps,
        uint256 blockNumberish
    ) internal view {
        _handleExclusiveOverride(order, exclusive, exclusivityEnd, exclusivityOverrideBps, blockNumberish);
    }

    /// @notice Applies exclusivity override to the resolved order if necessary
    /// @param order The order to apply exclusivity override to
    /// @param exclusive The exclusive address
    /// @param exclusivityEnd The exclusivity end timestamp or block number
    /// @param exclusivityOverrideBps The exclusivity override BPS
    /// @param currentPosition The block timestamp or number to determine exclusivity
    function _handleExclusiveOverride(
        ResolvedOrder memory order,
        address exclusive,
        uint256 exclusivityEnd,
        uint256 exclusivityOverrideBps,
        uint256 currentPosition
    ) internal view {
        // if the filler has fill right, we proceed with the order as-is
        if (hasFillingRights(exclusive, exclusivityEnd, currentPosition)) {
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
            output.amount = output.amount.mulDivUp(BPS + exclusivityOverrideBps, BPS);

            unchecked {
                i++;
            }
        }
    }

    /// @notice checks if the caller currently has filling rights on the order
    /// @param exclusive The exclusive address
    /// @param exclusivityEnd The exclusivity end timestamp or block number
    /// @param currentPosition The timestamp or block number to determine exclusivity
    /// @dev if the order has no exclusivity, always returns true
    /// @dev if the order has active exclusivity and the current filler is the exclusive address, returns true
    /// @dev if the order has active exclusivity and the current filler is not the exclusive address, returns false
    function hasFillingRights(address exclusive, uint256 exclusivityEnd, uint256 currentPosition)
        internal
        view
        returns (bool)
    {
        return exclusive == address(0) || currentPosition > exclusivityEnd || exclusive == msg.sender;
    }
}
