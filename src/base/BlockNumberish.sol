// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IArbSys} from "../interfaces/IArbSys.sol";

/// @title BlockNumberish
/// A helper contract to get the current block number on different chains
contract BlockNumberish {
    // Declare an immutable function type variable for the _getTstorish function
    // based on chain support for tstore at time of deployment.
    function() view returns (uint256) internal immutable _getBlockNumberish;

    constructor() {
        // Set the function to use based on chainid
        if (block.chainid == 42161) {
            _getBlockNumberish = _getBlockNumberSyscall;
        } else {
            _getBlockNumberish = _getBlockNumber;
        }
    }

    /// @dev Private function to get the block number on arbitrum
    function _getBlockNumberSyscall() private view returns (uint256) {
        return IArbSys(0x0000000000000000000000000000000000000064).arbBlockNumber();
    }

    /// @dev Private function to get the block number using the opcode
    function _getBlockNumber() private view returns (uint256) {
        return block.number;
    }
}
