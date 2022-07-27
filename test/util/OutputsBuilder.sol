// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Output} from "../../src/interfaces/ReactorStructs.sol";

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
}
