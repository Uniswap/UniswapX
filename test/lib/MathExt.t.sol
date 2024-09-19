// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {NonlinearDutchDecayLib} from "../../src/lib/NonlinearDutchDecayLib.sol";
import {V3DutchOutput, V3DutchInput, NonlinearDutchDecay} from "../../src/lib/V3DutchOrderLib.sol";
import {MathExt} from "../../src/lib/MathExt.sol";
import {ArrayBuilder} from "../util/ArrayBuilder.sol";

contract MathExtTest is Test {
    using MathExt for uint256;

    /* sub(uint256 a, int256 b) tests */

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
        vm.expectRevert();
        uint256(1).sub(int256(2));
    }

    function testSubIntFromUintOverflow() public {
        vm.expectRevert();
        UINT256_MAX.sub(-1);
    }

    /* boundedSub(uint256 a, int256 b, uint256 min, uint256 max) tests */

    function testBoundedSub(uint128 a, int128 b, uint256 max, uint256 min) public {
        vm.assume(max >= min);
        uint256 c = uint256(a).boundedSub(b, max, min);
        assertGe(c, min);
        assertLe(c, max);
    }

    function testBoundedSubNegIntFromUintRange(uint256 a, uint256 b) public {
        vm.assume(a < 2 ** 255 - 1);
        vm.assume(b <= UINT256_MAX - a);
        assertEq(b.boundedSub(0 - int256(a), 0, type(uint256).max), b + a);
    }

    function testBoundedSubIntFromUintRange(uint256 a, uint256 b) public {
        vm.assume(a >= 0);
        vm.assume(b >= a);
        vm.assume(a < 2 ** 255 - 1);
        assertEq(b.boundedSub(int256(a), 0, type(uint256).max), b - a);
    }

    function testBoundedSubIntFromUintNegativeUint() public {
        assertEq(uint256(1).boundedSub(int256(2), 0, type(uint256).max), 0);
    }

    function testBoundedSubIntFromUintOverflow() public {
        assertEq(UINT256_MAX.boundedSub(-1, 0, type(uint256).max), type(uint256).max);
    }

    /* sub(uint256 a, uint256 b) tests */

    function testSubUintFromUint() public {
        assertEq(uint256(2).sub(uint256(2)), 0);
        assertEq(uint256(2).sub(uint256(1)), 1);
        assertEq(uint256(2).sub(uint256(3)), -1);
    }

    function testSubUintFromUintRange(uint256 a, uint256 b) public {
        vm.assume(a >= b);
        vm.assume(a < 2 ** 255 - 1);
        assertEq(a.sub(b), int256(a - b));
    }

    function testSubUintFromUintNegativeUint(uint256 a, uint256 b) public {
        vm.assume(b >= a);
        vm.assume(b < 2 ** 255 - 1);
        int256 c = a.sub(b);
        assertEq(c, int256(a) - int256(b));
    }

    function testSubUintFromUintUnderflow() public {
        vm.expectRevert();
        uint256(0).sub(type(uint256).max);
    }

    function testSubUintFromUintOverflow() public {
        vm.expectRevert();
        UINT256_MAX.sub(uint256(1));
    }

    /* bound(uint256 value, uint256 min, uint256 max) */

    function testBound(uint256 value, uint256 min, uint256 max) public {
        vm.assume(min <= max);
        uint256 result = value.bound(min, max);
        assertLe(result, max);
        assertGe(result, min);
    }

    function testBoundValueInBounds(uint256 value, uint256 min, uint256 max) public {
        vm.assume(min <= value);
        vm.assume(value <= max);
        uint256 result = value.bound(min, max);
        assertEq(result, value);
    }
}
