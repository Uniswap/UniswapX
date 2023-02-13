// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {OrderInfo, ResolvedOrder, OutputToken} from "../base/ReactorStructs.sol";
import {IValidationCallback} from "../interfaces/IValidationCallback.sol";

library ResolvedOrderLib {
    error InvalidReactor();
    error DeadlinePassed();
    error ValidationFailed();
    error InsufficientOutput();

    struct AddressBalance {
        address recipient;
        address token;
        uint256 expectedBalance;
    }

    /// @notice Validates a resolved order, reverting if invalid
    /// @param filler The filler of the order
    function validate(ResolvedOrder memory resolvedOrder, address filler) internal view {
        if (address(this) != resolvedOrder.info.reactor) {
            revert InvalidReactor();
        }

        if (block.timestamp > resolvedOrder.info.deadline) {
            revert DeadlinePassed();
        }

        if (
            resolvedOrder.info.validationContract != address(0)
                && !IValidationCallback(resolvedOrder.info.validationContract).validate(filler, resolvedOrder)
        ) {
            revert ValidationFailed();
        }
    }

    /// @notice fetches expected post-fill balances for all recipient-token output pairs
    function getExpectedBalances(ResolvedOrder[] memory orders)
        internal
        view
        returns (AddressBalance[] memory expectedBalances)
    {
        // get the total number of outputs
        // note this is an upper bound on the length of the resulting array
        // because (recipient, token) pairs are deduplicated
        unchecked {
            uint256 outputCount = 0;
            for (uint256 i = 0; i < orders.length; i++) {
                outputCount += orders[i].outputs.length;
            }
            expectedBalances = new AddressBalance[](outputCount);
        }

        uint256 outputIdx = 0;

        // for each unique output (recipient, token) pair, add an entry to expectedBalances that
        // includes the user's initial balance + expected output
        for (uint256 i = 0; i < orders.length; i++) {
            ResolvedOrder memory order = orders[i];

            for (uint256 j = 0; j < order.outputs.length; j++) {
                OutputToken memory output = order.outputs[j];

                // check if the given output (address, token) pair already exists in expectedBalances
                // update it if so
                bool found = false;
                for (uint256 k = 0; k < expectedBalances.length; k++) {
                    AddressBalance memory addressBalance = expectedBalances[k];
                    if (addressBalance.recipient == output.recipient && addressBalance.token == output.token) {
                        found = true;
                        addressBalance.expectedBalance += output.amount;
                    } else if (addressBalance.token == address(0)) {
                        break;
                    }
                }

                if (!found) {
                    uint256 balance = ERC20(output.token).balanceOf(output.recipient);
                    expectedBalances[outputIdx] = AddressBalance({
                        recipient: output.recipient,
                        token: output.token,
                        expectedBalance: balance + output.amount
                    });
                    outputIdx++;
                }
            }
        }

        assembly {
            mstore(expectedBalances, outputIdx)
        }
    }

    /// @notice Asserts expected balances are satisfied
    function check(AddressBalance[] memory expectedBalances) internal view {
        for (uint256 i = 0; i < expectedBalances.length; i++) {
            AddressBalance memory expected = expectedBalances[i];
            uint256 balance = ERC20(expected.token).balanceOf(expected.recipient);
            if (balance < expected.expectedBalance) {
                revert InsufficientOutput();
            }
        }
    }
}
