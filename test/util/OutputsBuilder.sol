// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Output} from "../../src/interfaces/ReactorStructs.sol";
import {DutchOutput} from "../../src/reactor/dutch-limit/DutchLimitOrderStructs.sol";

library OutputsBuilder {
    function single(address token, uint256 amount, address recipient)
        internal
        pure
        returns (Output[] memory)
    {
        Output[] memory result = new Output[](1);
        result[0] = Output(token, amount, recipient);
        return result;
    }

    function singleDutch(address token, uint256 startAmount, uint256 endAmount, address recipient)
        internal
        pure
        returns (DutchOutput[] memory)
    {
        DutchOutput[] memory result = new DutchOutput[](1);
        result[0] = DutchOutput(token, startAmount, endAmount, recipient);
        return result;
    }

    // Returns array of dutch outputs. <startAmounts> and <endAmounts> have same length.
    // All dutch outputs will be of the same <token> and have the same <recipient>.
    function multipleDutch(
        address token,
        uint256[] memory startAmounts,
        uint256[] memory endAmounts,
        address recipient
    ) internal pure returns (DutchOutput[] memory) {
        DutchOutput[] memory result = new DutchOutput[](startAmounts.length);
        for (uint i = 0; i < startAmounts.length; i++) {
            result[i] = DutchOutput(token, startAmounts[i], endAmounts[i], recipient);
        }
        return result;
    }
}
