// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {OrderInfo, ResolvedOrder, OutputToken} from "../base/ReactorStructs.sol";
import {CurrencyLibrary} from "./CurrencyLibrary.sol";

struct ExpectedBalance {
    address recipient;
    address token;
    uint256 expectedBalance;
}

library ExpectedBalanceLib {
    using CurrencyLibrary for address;

    error InsufficientOutput();

    /// @notice fetches expected post-fill balances for all recipient-token output pairs
    function getExpectedBalances(ResolvedOrder[] memory orders)
        internal
        view
        returns (ExpectedBalance[] memory expectedBalances)
    {
        // get the total number of outputs
        // note this is an upper bound on the length of the resulting array
        // because (recipient, token) pairs are deduplicated
        unchecked {
            uint256 outputCount = 0;
            for (uint256 i = 0; i < orders.length; i++) {
                outputCount += orders[i].outputs.length;
            }
            expectedBalances = new ExpectedBalance[](outputCount);
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
                    ExpectedBalance memory addressBalance = expectedBalances[k];
                    if (addressBalance.recipient == output.recipient && addressBalance.token == output.token) {
                        found = true;
                        addressBalance.expectedBalance += output.amount;
                    } else if (addressBalance.token == address(0)) {
                        break;
                    }
                }

                if (!found) {
                    uint256 balance = output.token.balanceOf(output.recipient);
                    expectedBalances[outputIdx] = ExpectedBalance({
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
    function check(ExpectedBalance[] memory expectedBalances) internal view {
        for (uint256 i = 0; i < expectedBalances.length; i++) {
            ExpectedBalance memory expected = expectedBalances[i];
            uint256 balance = expected.token.balanceOf(expected.recipient);
            if (balance < expected.expectedBalance) {
                revert InsufficientOutput();
            }
        }
    }
}
