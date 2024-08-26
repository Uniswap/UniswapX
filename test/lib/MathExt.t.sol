// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {NonLinearDutchDecayLib} from "../../src/lib/NonLinearDutchDecayLib.sol";
import {NonLinearDutchOutput, NonLinearDutchInput, NonLinearDecay} from "../../src/lib/NonLinearDutchOrderLib.sol";
import {sub, NegativeUint} from "../../src/lib/MathExt.sol";
import {ArrayBuilder} from "../util/ArrayBuilder.sol";

contract MathExtTest is Test {
    using {sub} for uint256;

    function testSubIntFromUint() public {
        assertEq(uint256(2).sub(2), 0);
        assertEq(uint256(2).sub(1), 1);
        assertEq(uint256(2).sub(-1), 3);
    }

    function testSubNegIntFromUintRange(uint256 a, uint256 b) public {
        vm.assume(a < 2 ** 255 - 1);
        vm.assume(b <= UINT256_MAX - a);
        assertEq(b.sub(0 - int256(a)), b + a);
    }

    function testSubIntFromUintRange(uint256 a, uint256 b) public {
        vm.assume(a >= 0);
        vm.assume(b >= a);
        vm.assume(a < 2 ** 255 - 1);
        assertEq(b.sub(int256(a)), b - a);
    }

    function testSubIntFromUintNegativeUint() public {
        vm.expectRevert(NegativeUint.selector);
        uint256(1).sub(2);
    }

    function testSubIntFromUintOverflow() public {
        vm.expectRevert();
        UINT256_MAX.sub(-1);
    }
}
