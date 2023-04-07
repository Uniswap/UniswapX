// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.19;

import {OrderInfo, ResolvedOrder} from "../../../src/base/ReactorStructs.sol";
import {ExpectedBalance, ExpectedBalanceLib} from "../../../src/lib/ExpectedBalanceLib.sol";

// needed to assert reverts as vm.expectRevert doesnt work on internal library calls
contract MockExpectedBalanceLib {
    using ExpectedBalanceLib for ExpectedBalance[];

    function check(ExpectedBalance[] memory expected) external view {
        expected.check();
    }
}
