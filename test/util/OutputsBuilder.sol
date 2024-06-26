// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {MockERC20} from "../util/mock/MockERC20.sol";
import {OutputToken} from "../../src/base/ReactorStructs.sol";
import {DutchOutput} from "../../src/reactors/DutchOrderReactor.sol";
import {PriorityOutput} from "../../src/lib/PriorityOrderLib.sol";

library OutputsBuilder {
    function single(address token, uint256 amount, address recipient) internal pure returns (OutputToken[] memory) {
        OutputToken[] memory result = new OutputToken[](1);
        result[0] = OutputToken(token, amount, recipient);
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
            result[i] = OutputToken(token, amounts[i], recipient);
        }
        return result;
    }

    function singleDutch(MockERC20 token, uint256 startAmount, uint256 endAmount, address recipient)
        internal
        pure
        returns (DutchOutput[] memory)
    {
        return OutputsBuilder.singleDutch(address(token), startAmount, endAmount, recipient);
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

    function multipleDutch(
        MockERC20 token,
        uint256[] memory startAmounts,
        uint256[] memory endAmounts,
        address recipient
    ) internal pure returns (DutchOutput[] memory) {
        return OutputsBuilder.multipleDutch(address(token), startAmounts, endAmounts, recipient);
    }

    // Returns array of dutch outputs. <startAmounts> and <endAmounts> have same length.
    /// TODO: Support multiple tokens + recipients
    function multipleDutch(address token, uint256[] memory startAmounts, uint256[] memory endAmounts, address recipient)
        internal
        pure
        returns (DutchOutput[] memory)
    {
        DutchOutput[] memory result = new DutchOutput[](startAmounts.length);
        for (uint256 i = 0; i < startAmounts.length; i++) {
            result[i] = DutchOutput(token, startAmounts[i], endAmounts[i], recipient);
        }
        return result;
    }

    function singlePriority(address token, uint256 amount, uint256 mpsPerPriorityFeeWei, address recipient)
        internal
        pure
        returns (PriorityOutput[] memory)
    {
        PriorityOutput[] memory result = new PriorityOutput[](1);
        result[0] = PriorityOutput(token, amount, mpsPerPriorityFeeWei, recipient);
        return result;
    }

    function multiplePriority(address token, uint256[] memory amounts, uint256 mpsPerPriorityFeeWei, address recipient)
        internal
        pure
        returns (PriorityOutput[] memory)
    {
        PriorityOutput[] memory result = new PriorityOutput[](amounts.length);
        for (uint256 i = 0; i < amounts.length; i++) {
            result[i] = PriorityOutput(token, amounts[i], mpsPerPriorityFeeWei, recipient);
        }
        return result;
    }
}
