// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IValidationCallback} from "../interfaces/IValidationCallback.sol";
import {ResolvedOrder} from "../base/ReactorStructs.sol";
import {ISwapRouter02} from "../external/ISwapRouter02.sol";

/// @notice Validation contract that checks
/// @dev uses swapRouter02
contract PriceOracleValidation is IValidationCallback {
    error FailedToCallValidationContract(bytes reason);
    error InsufficientOutput(uint256 minOutput, uint256 actualOutput);

    function validate(address, ResolvedOrder calldata resolvedOrder) external {
        (address to, bytes memory data) = abi.decode(resolvedOrder.info.additionalValidationData, (address, bytes));

        // No strict interface enforced here
        (bool success, bytes memory returnData) = address(to).call(data);
        if (!success) {
            revert FailedToCallValidationContract(returnData);
        }
        uint256 amountOut = abi.decode(returnData, (uint256));

        uint256 totalOutputAmount;
        for (uint256 i = 0; i < resolvedOrder.outputs.length; i++) {
            totalOutputAmount += resolvedOrder.outputs[i].amount;
        }
        if (amountOut < totalOutputAmount) {
            revert InsufficientOutput(amountOut, totalOutputAmount);
        }
    }
}
