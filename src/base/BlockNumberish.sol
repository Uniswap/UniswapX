// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IArbSys} from "../interfaces/IArbSys.sol";

/// @title BlockNumberish
/// A helper contract to get the current block number on different chains
/// inspired by https://github.com/ProjectOpenSea/tstorish/blob/main/src/Tstorish.sol
contract BlockNumberish {
    // Declare an immutable function type variable for the _getBlockNumberish function
    function() view returns (uint256) internal immutable _getBlockNumberish;

    uint256 private constant ARB_CHAIN_ID = 42161;
    address private constant ARB_SYS_ADDRESS = 0x0000000000000000000000000000000000000064;

    constructor() {
        // Set the function to use based on chainid
        if (block.chainid == ARB_CHAIN_ID) {
            _getBlockNumberish = _getBlockNumberSyscall;
        } else {
            _getBlockNumberish = _getBlockNumber;
        }
    }

    /// @dev Private function to get the block number on arbitrum
    function _getBlockNumberSyscall() private view returns (uint256) {
        return IArbSys(ARB_SYS_ADDRESS).arbBlockNumber();
    }

    /// @dev Private function to get the block number using the opcode
    function _getBlockNumber() private view returns (uint256) {
        return block.number;
    }
}
