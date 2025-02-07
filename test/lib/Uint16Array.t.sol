// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {NonlinearDutchDecayLib} from "../../src/lib/NonlinearDutchDecayLib.sol";
import {V3DutchOutput, V3DutchInput, NonlinearDutchDecay} from "../../src/lib/V3DutchOrderLib.sol";
import {ArrayBuilder} from "../util/ArrayBuilder.sol";
import {
    Uint16ArrayLibrary,
    Uint16Array,
    toUint16Array,
    InvalidArrLength,
    IndexOutOfBounds
} from "../../src/types/Uint16Array.sol";

contract Uint16ArrayTest is Test {
    using Uint16ArrayLibrary for Uint16Array;

    function testGetElement(uint16 value, uint16 length) public {
        vm.assume(length <= 16);
        Uint16Array packedArr = toUint16Array(ArrayBuilder.fillUint16(length, value));
        for (uint256 i = 0; i < length; i++) {
            assertEq(packedArr.getElement(i), value);
        }
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testToUint16ArrayRevert() public {
        vm.expectRevert(InvalidArrLength.selector);
        toUint16Array(ArrayBuilder.fillUint16(17, 1));
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testGetElementRevert() public {
        Uint16Array packedArr = toUint16Array(ArrayBuilder.fillUint16(5, 1));
        vm.expectRevert(IndexOutOfBounds.selector);
        packedArr.getElement(16);
    }
}
