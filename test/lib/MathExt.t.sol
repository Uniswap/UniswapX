// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {NonlinearDutchDecayLib} from "../../src/lib/NonlinearDutchDecayLib.sol";
import {V3DutchOutput, V3DutchInput, NonlinearDutchDecay} from "../../src/lib/V3DutchOrderLib.sol";
import {MathExt, NegativeUint} from "../../src/lib/MathExt.sol";
import {ArrayBuilder} from "../util/ArrayBuilder.sol";

contract MathExtTest is Test {
    using MathExt for uint256;

    function testSubIntFromUint() public {
        assertEq(uint256(2).sub(int256(2)), 0);
        assertEq(uint256(2).sub(int256(1)), 1);
        assertEq(uint256(2).sub(int256(-1)), 3);
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
        uint256(1).sub(int256(2));
    }

    function testSubIntFromUintOverflow() public {
        vm.expectRevert();
        UINT256_MAX.sub(-1);
    }

    function testSubUintFromUint() public {
        assertEq(uint256(2).sub(uint256(2)), 0);
        assertEq(uint256(2).sub(uint256(1)), 1);
        assertEq(uint256(2).sub(uint256(3)), -1);
    }

    function testSubUintFromUintUnderflow() public {
        vm.expectRevert();
        uint256(0).sub(type(uint256).max);
    }

    function testBoundedSub(uint128 a, int128 b, uint256 max, uint256 min) public {
        vm.assume(max >= min);
        uint256 c = uint256(a).boundedSub(b, max, min);
        assertGe(c, min);
        assertLe(c, max);
    }
}
