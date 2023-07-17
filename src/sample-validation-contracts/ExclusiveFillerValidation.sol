// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IValidationCallback} from "../interfaces/IValidationCallback.sol";
import {ResolvedOrder, OrderInfo} from "../base/ReactorStructs.sol";

contract ExclusiveFillerValidation is IValidationCallback {
    /// @notice thrown if the filler does not have fill rights
    error NotExclusiveFiller(address filler);

    /// @notice verify that the filler exclusivity is satisfied
    /// @dev reverts if invalid filler given the exclusivity parameters
    /// @param filler The filler of the order
    /// @param resolvedOrder The order data to validate
    function validate(address filler, ResolvedOrder calldata resolvedOrder) external view {
        (address exclusiveFiller, uint256 lastExclusiveTimestamp) =
            abi.decode(resolvedOrder.info.additionalValidationData, (address, uint256));
        if (lastExclusiveTimestamp >= block.timestamp && filler != exclusiveFiller) {
            revert NotExclusiveFiller(filler);
        }
    }
}
