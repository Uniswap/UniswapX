// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.16;

import {OutputToken} from "../../src/base/ReactorStructs.sol";
import {DutchOutput} from "../../src/reactors/DutchLimitOrderReactor.sol";

library OutputsBuilder {
    function single(address token, uint256 amount, address recipient) internal pure returns (OutputToken[] memory) {
        OutputToken[] memory result = new OutputToken[](1);
        result[0] = OutputToken(token, amount, recipient, false);
        return result;
    }

    /// TODO: Support multiple tokens + recipients
    function multiple(address token, uint256[] memory amounts, address recipient)
        internal
        pure
        returns (OutputToken[] memory)
    {
        OutputToken[] memory result = new OutputToken[](amounts.length);
        for (uint256 i = 0; i < amounts.length; i++) {
            result[i] = OutputToken(token, amounts[i], recipient, false);
        }
        return result;
    }

    function singleDutch(address token, uint256 startAmount, uint256 endAmount, address recipient)
        internal
        pure
        returns (DutchOutput[] memory)
    {
        DutchOutput[] memory result = new DutchOutput[](1);
        result[0] = DutchOutput(token, startAmount, endAmount, recipient, false);
        return result;
    }

    // Returns array of dutch outputs. all parameters must have the same length.
    function multipleDutch(address[] memory tokens, uint256[] memory startAmounts, uint256[] memory endAmounts, address[] memory recipients)
        internal
        pure
        returns (DutchOutput[] memory)
    {
        require(tokens.length == startAmounts.length, "OutputsBuilder: token.length != startAmounts.length");
        require(tokens.length == endAmounts.length, "OutputsBuilder: token.length != endAmounts.length");
        require(tokens.length == recipients.length, "OutputsBuilder: token.length != recipient.length");
        
        DutchOutput[] memory result = new DutchOutput[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            result[i] = DutchOutput(tokens[i], startAmounts[i], endAmounts[i], recipients[i], false);
        }
        return result;
    }
}
