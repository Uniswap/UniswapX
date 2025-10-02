// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IPreExecutionHook} from "../../../../src/v4/interfaces/IHook.sol";
import {IReactor} from "../../../../src/v4/interfaces/IReactor.sol";
import {ResolvedOrder} from "../../../../src/v4/base/ReactorStructs.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {IPreExecutionHook} from "../../../../src/v4/interfaces/IHook.sol";
import {TokenTransferLib} from "../../../../src/v4/lib/TokenTransferLib.sol";

contract MockPreExecutionHook is IPreExecutionHook {
    IPermit2 public permit2;
    IReactor public reactor;

    error MockPreExecutionError();

    bool public isValid = true;
    mapping(address => bool) public invalidFillers; // true means invalid

    // State tracking for testing state modifications
    uint256 public preExecutionCounter;
    mapping(address => uint256) public fillerExecutions;

    modifier onlyReactor() {
        require(msg.sender == address(reactor));
        _;
    }

    constructor(IPermit2 _permit2, IReactor _reactor) {
        permit2 = _permit2;
        reactor = _reactor;
    }

    function preExecutionHook(address filler, ResolvedOrder calldata resolvedOrder) external override onlyReactor {
        _beforeTokenTransfer(filler, resolvedOrder);
        TokenTransferLib.signatureTransferInputTokens(permit2, resolvedOrder, filler);
    }

    function setValid(bool _valid) external {
        isValid = _valid;
    }

    function setFillerValid(address filler, bool valid) external {
        invalidFillers[filler] = !valid; // If valid is true, set invalidity to false
    }

    /// @notice Override the before hook to add custom validation
    function _beforeTokenTransfer(address filler, ResolvedOrder calldata) internal {
        // First check global validity
        if (!isValid) {
            revert MockPreExecutionError();
        }

        // Check filler-specific validity (reverts if filler is marked as invalid)
        if (invalidFillers[filler]) {
            revert MockPreExecutionError();
        }

        // Track state modifications (demonstrating non-view capability)
        preExecutionCounter++;
        fillerExecutions[filler]++;
    }
}
