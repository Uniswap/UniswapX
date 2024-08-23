// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {NonLinearDutchDecayLib} from "../../src/lib/NonLinearDutchDecayLib.sol";
import {NonLinearDutchOutput, NonLinearDutchInput, NonLinearDecay} from "../../src/lib/NonLinearDutchOrderLib.sol";
import {Util} from "../../src/lib/Util.sol";
import {ArrayBuilder} from "../util/ArrayBuilder.sol";

contract UtilTest is Test {

    function testSubIntFromUint() public {
        assertEq(Util.subIntFromUint(2, 2), 0);
        assertEq(Util.subIntFromUint(1, 2), 1);
        assertEq(Util.subIntFromUint(-1, 2), 3);
    }

    function testSubNegIntFromUintRange(uint256 a, uint256 b) public {
        vm.assume(a < 2**255-1);
        vm.assume(b <= UINT256_MAX - a);
        assertEq(Util.subIntFromUint(0-int256(a), b), b+a);
    }

    function testSubIntFromUintRange(uint256 a, uint256 b) public {
        vm.assume(a >= 0);
        vm.assume(b >= a);
        vm.assume(a < 2**255-1);
        assertEq(Util.subIntFromUint(int256(a), b), b-a);
    }

    function testSubIntFromUintNegativeUint() public {
        vm.expectRevert(Util.NegativeUint.selector);
        Util.subIntFromUint(2, 1);
    }

    function testSubIntFromUintOverflow() public {
        vm.expectRevert();
        Util.subIntFromUint(-1, UINT256_MAX);
    }

    function testGetUint16FromPacked(uint16 value, uint256 length) public {
        vm.assume(length <= 16);
        uint256 packedArr = Util.packUint16Array(ArrayBuilder.fillUint16(length, value));
        for (uint256 i = 0; i < length; i++) {
            assertEq(Util.getUint16FromPacked(packedArr, i), value);
        }
    }
}