// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IValidationCallback} from "../interfaces/IValidationCallback.sol";
import {ResolvedOrder} from "../base/ReactorStructs.sol";
import {ISwapRouter02} from "../external/ISwapRouter02.sol";

/// @notice Helper contract to call MixedRouteQuoterV1 and decode the return data
contract MixedRouteQuoterV1Wrapper {
    address private immutable quoter;

    constructor(address _quoter) {
        quoter = _quoter;
    }

    fallback(bytes calldata data) external returns (bytes memory) {
        // quoteExactInput(bytes memory path, uint256 amountIn)
        if (msg.sig != 0xcdca1753) {
            revert("Invalid function call");
        }

        (bool success, bytes memory returnData) = address(quoter).call(data);
        if (!success) {
            revert("Failed to call quoter");
        }

        (uint256 amountOut,,,) = abi.decode(returnData, (uint256, uint160[], uint32[], uint256));
        return abi.encode(amountOut);
    }
}

/// @notice Validation contract that checks
/// @dev uses swapRouter02
contract PriceOracleValidation is IValidationCallback {
    error FailedToCallValidationContract(bytes reason);
    error InsufficientOutput(uint256 minOutput, uint256 actualOutput);

    function validate(address, ResolvedOrder calldata resolvedOrder) external view {
        (address to, bytes memory data) = abi.decode(resolvedOrder.info.additionalValidationData, (address, bytes));

        // No strict interface enforced here
        (bool success, bytes memory returnData) = address(to).staticcall(data);
        if (!success) {
            revert FailedToCallValidationContract(returnData);
        }
        uint256 amount = abi.decode(returnData, (uint256));

        uint256 totalOutputAmount;
        for (uint256 i = 0; i < resolvedOrder.outputs.length; i++) {
            totalOutputAmount += resolvedOrder.outputs[i].amount;
        }
        if (amount < totalOutputAmount) {
            revert InsufficientOutput(amount, totalOutputAmount);
        }
    }
}
