// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IPostExecutionHook} from "../../../../src/v4/interfaces/IHook.sol";
import {ResolvedOrder} from "../../../../src/v4/base/ReactorStructs.sol";

contract MockPostExecutionHook is IPostExecutionHook {
    error MockPostExecutionError();

    bool public shouldRevert = false;

    // State tracking for testing
    uint256 public postExecutionCounter;
    mapping(address => uint256) public fillerExecutions;
    mapping(address => uint256) public swapperExecutions;

    // Last order data for verification in tests
    address public lastFiller;
    address public lastSwapper;
    bytes32 public lastOrderHash;
    uint256 public lastInputAmount;
    uint256 public lastOutputAmount;

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    /// @inheritdoc IPostExecutionHook
    function postExecutionHook(address filler, ResolvedOrder calldata resolvedOrder) external override {
        if (shouldRevert) {
            revert MockPostExecutionError();
        }

        // Track state modifications
        postExecutionCounter++;
        fillerExecutions[filler]++;
        swapperExecutions[resolvedOrder.info.swapper]++;

        // Store last order data for test verification
        lastFiller = filler;
        lastSwapper = resolvedOrder.info.swapper;
        lastOrderHash = resolvedOrder.hash;
        lastInputAmount = resolvedOrder.input.amount;
        lastOutputAmount = resolvedOrder.outputs.length > 0 ? resolvedOrder.outputs[0].amount : 0;
    }

    // Helper functions for testing
    function reset() external {
        postExecutionCounter = 0;
        lastFiller = address(0);
        lastSwapper = address(0);
        lastOrderHash = bytes32(0);
        lastInputAmount = 0;
        lastOutputAmount = 0;
    }
}
