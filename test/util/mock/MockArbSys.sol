// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/// Mock Arbitrum syscall contract
contract MockArbSys {
    uint256 _blockNumber;

    /// @dev helper function to set the block number
    function setBlockNumber(uint256 blockNumber) external {
        _blockNumber = blockNumber;
    }

    /// @notice returns the block number
    function arbBlockNumber() external view returns (uint256) {
        return _blockNumber;
    }
}
