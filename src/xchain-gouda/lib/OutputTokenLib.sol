// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {OutputToken} from "../base/SettlementStructs.sol";

library OutputTokenLib {
    bytes private constant OUTPUT_TOKEN_TYPE =
        "OutputToken(address recipient,address token,uint256 amount,uint256 chainId)";
    bytes32 private constant OUTPUT_TOKEN_TYPE_HASH = keccak256(OUTPUT_TOKEN_TYPE);

    /// @notice returns the hash of an output token struct
    function hash(OutputToken memory output) internal pure returns (bytes32) {
        return
            keccak256(abi.encode(OUTPUT_TOKEN_TYPE_HASH, output.recipient, output.token, output.amount, output.chainId));
    }

    /// @notice returns the hash of an output token struct
    function hash(OutputToken[] memory outputs) internal pure returns (bytes32) {
        bytes32[] memory outputHashes = new bytes32[](outputs.length);
        for (uint256 i = 0; i < outputs.length; i++) {
            outputHashes[i] = hash(outputs[i]);
        }
        return keccak256(abi.encodePacked(outputHashes));
    }
}
